import SwiftUI
import UIKit
import AVKit
import AVFoundation

/// New screen: paste a share link, parse it, download the video
/// or single images to the photo library.
///
/// Backends: 洛天 for 抖音 / 小红书 / 快手 / B站, socialdownloader
/// for Instagram, vxTwitter/fxTwitter for X, Invidious (+ on-device
/// mux) for YouTube, and an optional self-hosted cobalt instance
/// for YouTube / X / Instagram at max quality. Only public posts
/// work; private / age- / region-restricted posts need a login
/// and fail at the parse step.
struct DownloadRootView: View {
    @AppStorage("cobaltInstanceURL") private var cobaltInstance = ""

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parseError: String?
    @State private var result: ParsedMedia?
    @State private var downloadingVideo = false
    @State private var downloadingImages: Set<String> = []
    @State private var downloadingAll = false
    @State private var showCobalt = false
    @State private var liveVideoURL: URL?
    @State private var liveVideoName = ""
    @State private var liveVideoDuration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimDuration: Double = 0
    @State private var isConvertingLive = false
    @State private var showPhotoPicker = false
    @State private var showVideoFilePicker = false
    @State private var player: AVPlayer?
    @State private var previewObserver: Any?
    @State private var sharingURL: URL?
    @State private var showingShare = false
    @State private var toastVisible = false
    @State private var toastText = ""
    @State private var toastID = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        inputCard
                        if let result {
                            resultSection(result)
                        }
                        liveSection
                        cobaltSection
                        footerNote
                    }
                    .padding(16)
                }
                if toastVisible {
                    DownloadToastView(text: toastText)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("视频解析")
            .navigationBarTitleDisplayMode(.inline)
            .background(ActivityView(isPresented: $showingShare, url: sharingURL))
            .background(
                PhotoVideoPicker(isPresented: $showPhotoPicker) { url in
                    handlePickedVideo(url)
                }
            )
            .background(
                VideoFilePicker(isPresented: $showVideoFilePicker) { url in
                    handlePickedVideo(url)
                }
            )
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("粘贴分享链接或口令…", text: $inputText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button("粘贴") {
                    inputText = UIPasteboard.general.string ?? ""
                }
                .buttonStyle(.bordered)
                Button("解析") {
                    Task { await runParse() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                Spacer()
            }
            if isParsing {
                ProgressView("解析中…")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            if let parseError {
                Text(parseError)
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
    }

    private func runParse() async {
        isParsing = true
        parseError = nil
        result = nil
        do {
            result = try await parseMedia(input: inputText, cobaltInstance: cobaltInstance)
        } catch {
            parseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isParsing = false
    }

    // MARK: - Results

    private func resultSection(_ parsed: ParsedMedia) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("识别到：\(parsed.platform.rawValue)")
                    .font(.headline)
                Spacer()
                Text("来源：\(parsed.source)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if parsed.videoURL != nil {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .font(.title2)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("视频")
                            .font(.headline)
                        Text(parsed.videoQuality ?? "视频文件")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if downloadingVideo {
                        ProgressView()
                    } else {
                        Button("下载") {
                            Task { await downloadVideo(parsed) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !parsed.images.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("图片 \(parsed.images.count) 张 · 点单张下载")
                            .font(.headline)
                        Spacer()
                        if downloadingAll {
                            ProgressView()
                        } else {
                            Button("全部下载") {
                                Task { await downloadAllImages(parsed.images) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(parsed.images, id: \.absoluteString) { url in
                            Button {
                                Task { await downloadSingleImage(url) }
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        default:
                                            Color.gray.opacity(0.2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    if downloadingImages.contains(url.absoluteString) {
                                        ProgressView()
                                            .padding(6)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Downloads

    private func downloadVideo(_ parsed: ParsedMedia) async {
        guard let videoURL = parsed.videoURL else { return }
        downloadingVideo = true
        defer { downloadingVideo = false }
        do {
            let videoFile = try await downloadFile(from: videoURL)
            let finalFile: URL
            if let audioURL = parsed.audioURL {
                let audioFile = try await downloadFile(from: audioURL, defaultExtension: "m4a")
                do {
                    finalFile = try await muxVideo(videoURL: videoFile, audioURL: audioFile)
                } catch {
                    shareFile(videoFile, message: "音画合成失败，已打开分享菜单")
                    return
                }
            } else {
                finalFile = videoFile
            }
            do {
                try await saveVideoToPhotos(finalFile)
                showToast("已保存到相册")
            } catch {
                shareFile(finalFile, message: "保存到相册失败，已打开分享菜单")
            }
        } catch {
            showToast("下载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    private func downloadSingleImage(_ url: URL) async {
        downloadingImages.insert(url.absoluteString)
        defer { downloadingImages.remove(url.absoluteString) }
        do {
            let data = try await downloadData(from: url)
            do {
                try await saveImageDataToPhotos(data)
                showToast("已保存到相册")
            } catch {
                shareImageData(data, message: "保存到相册失败，已打开分享菜单")
            }
        } catch {
            showToast("下载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    private func downloadAllImages(_ urls: [URL]) async {
        downloadingAll = true
        defer { downloadingAll = false }
        var saved = 0
        for url in urls {
            do {
                let data = try await downloadData(from: url)
                try await saveImageDataToPhotos(data)
                saved += 1
            } catch {
                continue
            }
        }
        showToast("已保存 \(saved)/\(urls.count) 张")
    }

    private func shareFile(_ url: URL, message: String?) {
        sharingURL = url
        showingShare = true
        if let message {
            showToast(message)
        }
    }

    private func shareImageData(_ data: Data, message: String?) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            shareFile(url, message: message)
        } catch {
            showToast("保存失败")
        }
    }

    // MARK: - Video -> Live Photo

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("视频转 Live Photo")
                .font(.headline)
            HStack(spacing: 12) {
                Button("从相册选视频") {
                    showPhotoPicker = true
                }
                .buttonStyle(.bordered)
                Button("从文件选视频") {
                    showVideoFilePicker = true
                }
                .buttonStyle(.bordered)
            }
            if liveVideoURL != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(liveVideoName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("时长 \(String(format: "%.1f", liveVideoDuration))s · 片段最长 3s，静态图取片段中间一帧")
                        .font(.caption)
                        .foregroundColor(.gray)
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Button("预览片段") {
                            previewSegment()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("从 \(String(format: "%.1f", trimStart))s 开始，共 \(String(format: "%.1f", trimDuration))s")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if liveVideoDuration > 0.5 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开始：\(String(format: "%.1f", trimStart))s")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Slider(value: $trimStart, in: 0...max(0, liveVideoDuration - 0.5), step: 0.1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("时长：\(String(format: "%.1f", trimDuration))s")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Slider(value: $trimDuration, in: 0.5...max(0.5, min(3.0, liveVideoDuration - trimStart)), step: 0.1)
                        }
                    } else {
                        Text("视频不足 0.5 秒，直接整段转换")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if isConvertingLive {
                        ProgressView("转换中…")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Button("转为 Live Photo") {
                            Task { await convertLive() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(liveVideoDuration <= 0)
                    }
                }
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func handlePickedVideo(_ url: URL) {
        if let oldPlayer = player, let token = previewObserver {
            oldPlayer.removeTimeObserver(token)
            previewObserver = nil
        }
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        let stable: URL
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            stable = dest
        } catch {
            stable = url
        }
        liveVideoURL = stable
        liveVideoName = url.lastPathComponent
        player = AVPlayer(url: stable)
        Task {
            let asset = AVURLAsset(url: stable)
            if let duration = try? await asset.load(.duration) {
                let seconds = duration.seconds
                liveVideoDuration = seconds
                trimStart = 0
                trimDuration = min(3.0, seconds)
            }
        }
    }

    private func previewSegment() {
        guard let player, liveVideoDuration > 0 else { return }
        if let token = previewObserver {
            player.removeTimeObserver(token)
            previewObserver = nil
        }
        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: min(trimStart + trimDuration, liveVideoDuration), preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        previewObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) {
            player.pause()
        }
        player.play()
    }

    private func convertLive() async {
        guard let url = liveVideoURL else { return }
        isConvertingLive = true
        defer { isConvertingLive = false }
        let duration = min(min(trimDuration, 3.0), max(0.1, liveVideoDuration - trimStart))
        do {
            try await convertVideoToLivePhoto(sourceURL: url, start: trimStart, duration: duration)
            showToast("已保存为 Live Photo，去相册长按播放")
        } catch {
            showToast("转换失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    // MARK: - Cobalt + footer

    private var cobaltSection: some View {
        DisclosureGroup("自建解析服务（可选）", isExpanded: $showCobalt) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("cobalt 实例地址，如 https://xxx.example.com", text: $cobaltInstance)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("填了之后，YouTube、X、Instagram 走这个实例解析（最高画质）。需要 cobalt 11+ 且无验证或自带密钥的实例；公开 api.cobalt.tools 需网页验证，App 内不可用。留空用默认路线。")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
    }

    private var footerNote: some View {
        Text("仅支持公开内容。私密、年龄或地区受限内容需登录，无法解析。视频和图片默认保存到相册；保存失败时会打开分享菜单。")
            .font(.caption)
            .foregroundColor(.gray)
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastID += 1
        let currentID = toastID
        toastText = message
        toastVisible = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastID == currentID {
                toastVisible = false
            }
        }
    }
}

/// Local toast (named differently from the card-code one on
/// purpose: same-named file-private types still collide in one
/// module, which broke an earlier build).
private struct DownloadToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
    }
}
