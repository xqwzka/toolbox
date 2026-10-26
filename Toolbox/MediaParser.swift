import Foundation

/// Platforms the download screen covers. Detection is by link
/// host; the parse backend differs per platform (see parseMedia).
enum DownloadPlatform: String {
    case douyin = "抖音"
    case xiaohongshu = "小红书"
    case kuaishou = "快手"
    case bilibili = "B站"
    case youtube = "YouTube"
    case instagram = "Instagram"
    case twitter = "X"
    case unknown = "未知"
}

/// One parse result: at most one video (YouTube may carry a
/// separate audio track to mux) plus zero or more images. Images
/// are always downloaded one by one; the grid never forces a
/// whole-album download.
struct ParsedMedia {
    let platform: DownloadPlatform
    let source: String
    let videoURL: URL?
    let videoQuality: String?
    let audioURL: URL?
    let images: [URL]
}

enum ParseError: Error, LocalizedError {
    case unsupported
    case message(String)
    case network

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "暂不支持这个链接"
        case .message(let text):
            return text
        case .network:
            return "网络错误，稍后重试"
        }
    }
}

// MARK: - Link handling

/// First URL in pasted share text. Falls back to a regex when
/// NSDataDetector finds nothing.
func extractFirstURL(from text: String) -> String? {
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector.firstMatch(in: text, range: range), let url = match.url {
            return url.absoluteString
        }
    }
    if let match = text.range(of: "https?://[^\\s]+", options: .regularExpression) {
        var found = String(text[match])
        while let last = found.last, "，。！？；、）)]".contains(last) {
            found.removeLast()
        }
        return found
    }
    return nil
}

func detectPlatform(_ urlString: String) -> DownloadPlatform {
    let lower = urlString.lowercased()
    if lower.contains("douyin.com") { return .douyin }
    if lower.contains("xiaohongshu.com") || lower.contains("xhslink.com") { return .xiaohongshu }
    if lower.contains("kuaishou.com") { return .kuaishou }
    if lower.contains("bilibili.com") || lower.contains("b23.tv") { return .bilibili }
    if lower.contains("youtube.com") || lower.contains("youtu.be") { return .youtube }
    if lower.contains("instagram.com") { return .instagram }
    if lower.contains("x.com") || lower.contains("twitter.com") { return .twitter }
    return .unknown
}

// MARK: - Networking helpers

private func fetchJSON(_ request: URLRequest) async throws -> Any {
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        throw ParseError.network
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        // Backends answer non-200 with a JSON error body (e.g.
        // socialdownloader 422 for rate-limited or private
        // posts). Surface that message instead of collapsing
        // every non-200 into a generic network error.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["error"] as? String, !message.isEmpty {
            throw ParseError.message(message)
        }
        throw ParseError.network
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) else {
        throw ParseError.message("解析服务返回了看不懂的数据")
    }
    return json
}

private func postJSON(url: String, body: [String: Any], userAgent: String? = nil) -> URLRequest {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let userAgent {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    return request
}

/// Recursively collect every dictionary in a JSON value.
private func allDicts(in value: Any) -> [[String: Any]] {
    var found: [[String: Any]] = []
    if let dict = value as? [String: Any] {
        found.append(dict)
        for child in dict.values {
            found.append(contentsOf: allDicts(in: child))
        }
    } else if let array = value as? [Any] {
        for child in array {
            found.append(contentsOf: allDicts(in: child))
        }
    }
    return found
}

private func dedupe(_ urls: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for url in urls where !seen.contains(url) {
        seen.insert(url)
        out.append(url)
    }
    return out
}

// MARK: - Dispatcher

/// Parse pasted share text or a bare link. When a self-hosted
/// cobalt instance is configured, YouTube / X / Instagram go
/// through it (videoQuality=max); everything else uses its
/// default backend.
func parseMedia(input: String, cobaltInstance: String?) async throws -> ParsedMedia {
    guard let urlString = extractFirstURL(from: input) else {
        throw ParseError.message("没有找到链接，粘贴分享文本或链接")
    }
    let platform = detectPlatform(urlString)
    guard platform != .unknown else {
        throw ParseError.unsupported
    }
    let cobalt = (cobaltInstance ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !cobalt.isEmpty, platform == .youtube || platform == .twitter || platform == .instagram {
        return try await parseCobalt(instance: cobalt, urlString: urlString, platform: platform)
    }
    switch platform {
    case .douyin, .xiaohongshu, .kuaishou, .bilibili:
        return try await parseLuotian(shareText: input, platform: platform)
    case .instagram:
        return try await parseInstagram(urlString)
    case .twitter:
        return try await parseX(urlString)
    case .youtube:
        return try await parseYouTube(urlString)
    case .unknown:
        throw ParseError.unsupported
    }
}

// MARK: - 洛天: 抖音 / 小红书 / 快手 / B站

/// Same backend as the video-download Shortcut: POST share_text,
/// take media_url. YouTube was probed twice against this API and
/// came back "ALAPI拒绝请求: 未知解析错误", so it is not routed
/// here. Response fields vary by platform, so video/image
/// candidates are collected by key name and file extension.
private func parseLuotian(shareText: String, platform: DownloadPlatform) async throws -> ParsedMedia {
    let json = try await fetchJSON(postJSON(url: "https://api.luotian.cyou/api/videojiexi", body: ["share_text": shareText]))
    if let dict = json as? [String: Any], let detail = dict["detail"] as? String {
        throw ParseError.message(detail)
    }
    var videos: [String] = []
    var images: [String] = []
    // Douyin's CDN links often carry no .mp4/.jpg suffix at all
    // (image hosts serve ~tplv-...image URLs, video hosts serve
    // bare videoplayback paths), so extension alone drops most
    // album items. The key name and the CDN host/path carry the
    // type instead: p-hosts and tos-cn-i/tos-alisg-i paths are
    // pictures, v-hosts and /video/ paths are video.
    enum KeyHint {
        case video
        case image
        case media
        case other
    }
    func classify(_ string: String, hint: KeyHint) {
        let lower = string.lowercased()
        guard lower.hasPrefix("http") else { return }
        if lower.contains(".mp4") || lower.contains(".mov") || lower.contains(".m3u8") {
            videos.append(string)
            return
        }
        if lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") || lower.contains(".image") {
            images.append(string)
            return
        }
        switch hint {
        case .image:
            images.append(string)
        case .video:
            videos.append(string)
        case .media:
            let host = URL(string: string)?.host?.lowercased() ?? ""
            let isDouyinCDN = host.contains("douyinpic") || host.contains("tiktokcdn")
            if isDouyinCDN, let first = host.first, first == "p" {
                images.append(string)
            } else if isDouyinCDN, let first = host.first, first == "v" {
                videos.append(string)
            } else if lower.contains("tos-cn-i-") || lower.contains("tos-alisg-i-") {
                images.append(string)
            } else if lower.contains("/video/") || lower.contains("tos-cn-p-") {
                videos.append(string)
            } else {
                videos.append(string)
            }
        case .other:
            break
        }
    }
    func scan(_ value: Any) {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                let keyLower = key.lowercased()
                let hint: KeyHint?
                if keyLower.contains("video") {
                    hint = .video
                } else if keyLower.contains("image") || keyLower.contains("pic") || keyLower.contains("img") {
                    hint = .image
                } else if keyLower.contains("media") {
                    hint = .media
                } else if keyLower == "url" {
                    hint = .other
                } else {
                    hint = nil
                }
                if let hint {
                    if let string = child as? String {
                        classify(string, hint: hint)
                    } else if let array = child as? [Any] {
                        for item in array {
                            if let string = item as? String {
                                classify(string, hint: hint)
                            }
                        }
                    }
                }
                scan(child)
            }
        } else if let array = value as? [Any] {
            for item in array {
                scan(item)
            }
        }
    }
    scan(json)
    videos = dedupe(videos)
    images = dedupe(images)
    // Prefer a plain mp4 over an HLS playlist when both show up.
    let videoURL = (videos.first(where: { $0.lowercased().contains(".mp4") }) ?? videos.first).flatMap(URL.init)
    guard videoURL != nil || !images.isEmpty else {
        throw ParseError.message("这个链接解析不到视频或图片")
    }
    return ParsedMedia(
        platform: platform,
        source: "洛天",
        videoURL: videoURL,
        videoQuality: nil,
        audioURL: nil,
        images: images.compactMap(URL.init)
    )
}

// MARK: - socialdownloader: Instagram

/// POST /api/download takes {"url": ...} (probed: a "link" field
/// answers "URL is required"). Successful items carry downloadUrl,
/// relative ones prefixed with the site host. Public posts, reels
/// and carousels only; private / age- / region-restricted posts
/// need a login and come back success=false.
private func parseInstagram(_ urlString: String) async throws -> ParsedMedia {
    // Browser UA: the no-UA app request was never verified
    // against a real post on-device; the browser test that
    // verified this endpoint used a browser UA.
    let json = try await fetchJSON(postJSON(url: "https://www.socialdownloader.space/api/download", body: ["url": urlString], userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"))
    if let dict = json as? [String: Any], dict["success"] as? Bool == false {
        throw ParseError.message(dict["error"] as? String ?? "解析失败")
    }
    var videos: [String] = []
    var images: [String] = []
    for dict in allDicts(in: json) {
        // downloadUrl is the media file. A bare "url" only counts
        // when the dict also carries a type (a media item), so
        // post-page URLs in metadata dicts are ignored.
        let hasType = dict["type"] is String
        guard var raw = dict["downloadUrl"] as? String ?? (hasType ? dict["url"] as? String : nil) else { continue }
        if raw.hasPrefix("/") {
            raw = "https://www.socialdownloader.space" + raw
        }
        guard raw.hasPrefix("http") else { continue }
        let type = (dict["type"] as? String ?? "").lowercased()
        let lower = raw.lowercased()
        if type.contains("video") || lower.contains(".mp4") || lower.contains(".mov") {
            videos.append(raw)
        } else if type.contains("image") || type.contains("photo")
            || lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") {
            images.append(raw)
        } else {
            // Extension-less CDN link, no type: usually a reel.
            videos.append(raw)
        }
    }
    videos = dedupe(videos)
    images = dedupe(images)
    guard !videos.isEmpty || !images.isEmpty else {
        throw ParseError.message("这个帖子解析不到可下载内容")
    }
    return ParsedMedia(
        platform: .instagram,
        source: "socialdownloader",
        videoURL: videos.first.flatMap(URL.init),
        videoQuality: nil,
        audioURL: nil,
        images: images.compactMap(URL.init)
    )
}

// MARK: - vxTwitter / fxTwitter: X

/// No-key tweet lookup. The native video_info variants carry
/// bitrates; the highest-bitrate mp4 is the original upload
/// quality. The walk is tolerant across both services' shapes.
private func parseX(_ urlString: String) async throws -> ParsedMedia {
    let pattern = "(?:x\\.com|twitter\\.com)/([^/\\?]+)/status/(\\d+)"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
          let userRange = Range(match.range(at: 1), in: urlString),
          let idRange = Range(match.range(at: 2), in: urlString) else {
        throw ParseError.message("认不出这条推文链接")
    }
    let user = String(urlString[userRange])
    let id = String(urlString[idRange])
    var lastError: Error = ParseError.message("这个帖子没有可下载的视频")
    for host in ["api.vxtwitter.com", "api.fxtwitter.com"] {
        var request = URLRequest(url: URL(string: "https://\(host)/\(user)/status/\(id)")!)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let json = try? await fetchJSON(request) else { continue }
        // Best: highest bitrate mp4, across both services' shapes.
        var bestURL: String?
        var bestBitrate = -1
        // Legacy shape: video_info variants.
        for dict in allDicts(in: json) {
            guard let variants = dict["video_info"] as? [String: Any],
                  let list = variants["variants"] as? [[String: Any]] else { continue }
            for variant in list {
                guard let variantURL = variant["url"] as? String,
                      variantURL.lowercased().contains(".mp4") else { continue }
                let bitrate = variant["bitrate"] as? Int ?? 0
                if bitrate > bestBitrate {
                    bestBitrate = bitrate
                    bestURL = variantURL
                }
            }
        }
        // Current fxTwitter shape: media items carry formats[]
        // and variants[] directly, with no video_info wrapper.
        // (This was the miss: the old code only knew video_info,
        // so real fxTwitter replies fell through to "no video".)
        for dict in allDicts(in: json) {
            if let formats = dict["formats"] as? [[String: Any]] {
                for format in formats {
                    guard let formatURL = format["url"] as? String,
                          formatURL.lowercased().contains(".mp4") else { continue }
                    let bitrate = format["bitrate"] as? Int ?? 0
                    if bitrate > bestBitrate {
                        bestBitrate = bitrate
                        bestURL = formatURL
                    }
                }
            }
            if let variants = dict["variants"] as? [[String: Any]] {
                for variant in variants {
                    guard let variantURL = variant["url"] as? String,
                          variantURL.lowercased().contains(".mp4") else { continue }
                    let bitrate = variant["bitrate"] as? Int ?? 0
                    if bitrate > bestBitrate {
                        bestBitrate = bitrate
                        bestURL = variantURL
                    }
                }
            }
        }
        if let found = bestURL {
            return ParsedMedia(platform: .twitter, source: host, videoURL: URL(string: found), videoQuality: nil, audioURL: nil, images: [])
        }
        // Fallback: any direct video.twimg.com mp4 link. The
        // re-serialized JSON escapes slashes (https:\/\/...),
        // so unescape before matching, or this never matches.
        if let dict = json as? [String: Any],
           let rawText = String(data: (try? JSONSerialization.data(withJSONObject: dict)) ?? Data(), encoding: .utf8),
           !rawText.isEmpty {
            let text = rawText.replacingOccurrences(of: "\\/", with: "/")
            if let match = text.range(of: "https://video\\.twimg\\.com/[^\"'\\s]+\\.mp4", options: .regularExpression) {
                return ParsedMedia(platform: .twitter, source: host, videoURL: URL(string: String(text[match])), videoQuality: nil, audioURL: nil, images: [])
            }
        }
        lastError = ParseError.message("这个帖子没有可下载的视频")
    }
    throw lastError
}

// MARK: - Invidious: YouTube

/// YouTube has no combined high-quality file from no-key APIs:
/// adaptiveFormats give video-only + audio-only streams, so the
/// app downloads the best avc1 mp4 video and the best mp4 audio
/// and muxes them (see MediaDownload.muxVideo). Instance list is
/// discovered live so a dead instance does not kill the feature.
private func parseYouTube(_ urlString: String) async throws -> ParsedMedia {
    guard let videoID = extractYouTubeID(urlString) else {
        throw ParseError.message("认不出这个 YouTube 链接")
    }
    let instances = await discoverInvidiousInstances()
    var lastError: Error = ParseError.network
    for domain in instances {
        var request = URLRequest(url: URL(string: "https://\(domain)/api/v1/videos/\(videoID)")!)
        request.timeoutInterval = 20
        guard let json = try? await fetchJSON(request),
              let dict = json as? [String: Any],
              let formats = dict["adaptiveFormats"] as? [[String: Any]] else {
            lastError = ParseError.network
            continue
        }
        struct Stream {
            let url: String
            let height: Int
            let bitrate: Int
            let codecs: String
        }
        var videos: [Stream] = []
        var audios: [Stream] = []
        for format in formats {
            guard let type = format["type"] as? String,
                  let url = format["url"] as? String else { continue }
            if type.hasPrefix("video/mp4") {
                let label = format["qualityLabel"] as? String ?? ""
                let height = Int(label.dropLast()) ?? 0
                videos.append(Stream(url: url, height: height, bitrate: format["bitrate"] as? Int ?? 0, codecs: type))
            } else if type.hasPrefix("audio/mp4") {
                audios.append(Stream(url: url, height: 0, bitrate: format["bitrate"] as? Int ?? 0, codecs: type))
            }
        }
        // avc1 (h264) video muxes cleanly to mp4 on-device;
        // prefer it, fall back to any mp4 video stream.
        let avcVideos = videos.filter { $0.codecs.contains("avc1") }
        let ranked = (avcVideos.isEmpty ? videos : avcVideos).sorted { $0.height > $1.height }
        guard let video = ranked.first else {
            lastError = ParseError.message("这个视频没有可下载的格式")
            continue
        }
        let audio = audios.sorted { $0.bitrate > $1.bitrate }.first
        let quality = "\(video.height)p" + (audio == nil ? " · 无声" : " · 含音频")
        return ParsedMedia(
            platform: .youtube,
            source: "Invidious (\(domain))",
            videoURL: URL(string: video.url),
            videoQuality: quality,
            audioURL: audio.map { URL(string: $0.url) } ?? nil,
            images: []
        )
    }
    throw lastError
}

private func extractYouTubeID(_ urlString: String) -> String? {
    guard let url = URL(string: urlString),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }
    if let value = components.queryItems?.first(where: { $0.name == "v" })?.value, !value.isEmpty {
        return value
    }
    let path = components.path
    for prefix in ["/shorts/", "/embed/", "/live/"] where path.hasPrefix(prefix) {
        return String(path.dropFirst(prefix.count)).components(separatedBy: "/").first
    }
    if let host = components.host, host.contains("youtu.be") {
        return String(path.dropFirst()).components(separatedBy: "/").first
    }
    return nil
}

private func discoverInvidiousInstances() async -> [String] {
    var domains: [String] = []
    if let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.invidious.io/instances.json")!),
       let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
        for item in list where item.count >= 2 {
            if let domain = item[0] as? String,
               let info = item[1] as? [String: Any],
               info["api"] as? Bool == true {
                domains.append(domain)
                if domains.count >= 4 { break }
            }
        }
    }
    if !domains.contains("yt.chocolatemoo53.com") {
        domains.append("yt.chocolatemoo53.com")
    }
    return domains
}

// MARK: - Cobalt (self-hosted instance only)

/// The public api.cobalt.tools instance now requires a web
/// Turnstile JWT and cannot be called from the app, so this path
/// only runs when the user enters their own instance URL.
/// videoQuality=max returns the best available file; picker
/// responses (carousels, multi-photo posts) map to images/video.
private func parseCobalt(instance: String, urlString: String, platform: DownloadPlatform) async throws -> ParsedMedia {
    let base = instance.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let json = try await fetchJSON(postJSON(url: base + "/", body: [
        "url": urlString,
        "videoQuality": "max",
        "youtubeVideoCodec": "h264",
        "filenameStyle": "basic",
    ]))
    guard let dict = json as? [String: Any],
          let status = dict["status"] as? String else {
        throw ParseError.message("cobalt 实例返回了看不懂的数据")
    }
    switch status {
    case "tunnel", "redirect":
        guard let raw = dict["url"] as? String, let url = URL(string: raw) else {
            throw ParseError.message("cobalt 没有返回下载地址")
        }
        let lower = raw.lowercased()
        if lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") {
            return ParsedMedia(platform: platform, source: "cobalt", videoURL: nil, videoQuality: nil, audioURL: nil, images: [url])
        }
        return ParsedMedia(platform: platform, source: "cobalt", videoURL: url, videoQuality: "最高画质", audioURL: nil, images: [])
    case "picker":
        var videos: [String] = []
        var images: [String] = []
        if let items = dict["picker"] as? [[String: Any]] {
            for item in items {
                guard let raw = item["url"] as? String else { continue }
                let type = (item["type"] as? String ?? "").lowercased()
                let lower = raw.lowercased()
                if type.contains("video") || lower.contains(".mp4") || lower.contains(".mov") {
                    videos.append(raw)
                } else {
                    images.append(raw)
                }
            }
        }
        guard !videos.isEmpty || !images.isEmpty else {
            throw ParseError.message("cobalt 没有返回可下载内容")
        }
        return ParsedMedia(platform: platform, source: "cobalt", videoURL: videos.first.flatMap(URL.init), videoQuality: "最高画质", audioURL: nil, images: images.compactMap(URL.init))
    case "error":
        let error = dict["error"] as? [String: Any]
        throw ParseError.message(error?["text"] as? String ?? error?["code"] as? String ?? "cobalt 解析失败")
    default:
        throw ParseError.message("cobalt 解析失败：\(status)")
    }
}
