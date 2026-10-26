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
    @State private var downloadingLivePhotos: Set<String> = []
    @State private var showCobalt = false
    @State private var liveVideoURL: URL?
    @State private var liveVideoName = ""
    @State private var liveVideoDuration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimDuration: Double = 0
    @State private var isConvertingLive = false
    @State private var liveDebugText = ""
    @State private var liveCrashText = ""
    @State private var showPhotoPicker = false
    @State private var showVideoFilePicker = false
    @State private var player: AVPlayer?
    @State private var viewingVideo: URL?
    @State private var viewingAudio: URL?
    @State private var viewingQuality: String?
    @StateObject private var videoProgress = VideoDownloadProgress()
    @State private var previewObserver: Any?
    @State private var sharingURL: URL?
    @State private var showingShare = false
    @State private var toastVisible = false
    @State private var toastText = ""
    @State private var toastID = 0

    /// Square thumbnail side: explicit frames, so a portrait
    /// image can never blow up a grid cell and overlap the
    /// sections below (the old aspectRatio(1, fill) chain did).
    private var gridCell: CGFloat {
        (UIScreen.main.bounds.width - 32 - 16) / 3
    }

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
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    // Bottom clearance: the floating switch
                    // button sits over the bottom ~175pt, so the
                    // convert button must scroll above it.
                    .padding(.bottom, 180)
                }
                .onAppear { refreshLiveDebug() }
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
            .fullScreenCover(isPresented: Binding(
                get: { viewingVideo != nil },
                set: { if !$0 { viewingVideo = nil; viewingAudio = nil; viewingQuality = nil } }
            )) {
                if let url = viewingVideo {
                    VideoViewerView(
                        url: url,
                        quality: viewingQuality,
                        isDownloading: downloadingVideo,
                        progress: videoProgress,
                        onDownload: {
                            Task { await downloadVideoURL(url, audioURL: viewingAudio) }
                        },
                        onClose: {
                            viewingVideo = nil
                            viewingAudio = nil
                            viewingQuality = nil
                        }
                    )
                }
            }
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
            let videoList = parsed.videos.isEmpty ? parsed.videoURL.map { [$0] } ?? [] : parsed.videos
            if !videoList.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("视频 \(videoList.count) 个 · 点开预览")
                            .font(.headline)
                        Spacer()
                        if let quality = parsed.videoQuality {
                            Text(quality)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(videoList, id: \.absoluteString) { url in
                            Button {
                                viewingVideo = url
                                viewingAudio = url == parsed.videoURL ? parsed.audioURL : nil
                                viewingQuality = url == parsed.videoURL ? parsed.videoQuality : nil
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    VideoThumbView(url: url, size: gridCell)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .padding(6)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !parsed.livePhotos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("动图 \(parsed.livePhotos.count) 张 · 保存为 Live Photo")
                        .font(.headline)
                    ForEach(parsed.livePhotos, id: \.videoURL.absoluteString) { item in
                        HStack(spacing: 12) {
                            AsyncImage(url: item.coverURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Photo")
                                    .font(.headline)
                                Text("静态图 + 动效视频，存为一张实况照片")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if downloadingLivePhotos.contains(item.videoURL.absoluteString) {
                                ProgressView()
                            } else {
                                Button("保存") {
                                    Task { await downloadLivePhoto(item) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
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
                                    .frame(width: gridCell, height: gridCell)
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

    /// Video download with retries: transport errors (dropped
    /// connection, timeout) get two more attempts; HTTP errors
    /// (403 etc.) fail immediately — retrying them is pointless.
    private func downloadVideoURL(_ videoURL: URL, audioURL: URL?) async {
        downloadingVideo = true
        defer { downloadingVideo = false }
        for attempt in 0..<3 {
            do {
                try await downloadVideoURLOnce(videoURL, audioURL: audioURL)
                return
            } catch is URLError {
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                showToast("下载失败，网络错误")
                return
            } catch {
                showToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }
        }
    }

    private func downloadVideoURLOnce(_ videoURL: URL, audioURL: URL?) async throws {
        let box = videoProgress
        box.fraction = 0
        defer { box.fraction = nil }
        let videoFile = try await downloadFileWithProgress(from: videoURL) { fraction in
            box.fraction = fraction
        }
        let finalFile: URL
        if let audioURL {
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
            viewingVideo = nil
            viewingAudio = nil
            viewingQuality = nil
        } catch {
            shareFile(finalFile, message: "保存到相册失败，已打开分享菜单")
        }
    }

    private func downloadLivePhoto(_ item: LivePhotoItem) async {
        downloadingLivePhotos.insert(item.videoURL.absoluteString)
        defer { downloadingLivePhotos.remove(item.videoURL.absoluteString) }
        liveDebugClear()
        liveDebugMark("开始下载动图")
        do {
            let coverData = try await downloadData(from: item.coverURL)
            guard let coverImage = UIImage(data: coverData),
                  let jpegData = coverImage.jpegData(compressionQuality: 0.92) else {
                showToast("动图封面读取失败")
                return
            }
            let videoFile = try await downloadFile(from: item.videoURL)
            liveDebugMark("动图下载完成，开始配对")
            try await saveLivePhotoPair(photoData: jpegData, videoURL: videoFile)
            showToast("已保存为 Live Photo，去相册长按播放")
        } catch {
            showToast("保存失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
        refreshLiveDebug()
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
            if !liveDebugText.isEmpty {
                Text("诊断：上次执行到「\(liveDebugText)」")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if !liveCrashText.isEmpty {
                Text("上次崩溃原因：\(liveCrashText)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(4)
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

    private func refreshLiveDebug() {
        liveDebugText = liveDebugLastLine()
        liveCrashText = liveCrashSummary()
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
        refreshLiveDebug()
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

/// One video thumbnail: a frame grabbed at 0.5s, or a play icon
/// tile when the frame cannot be read (HLS, dead link). The
/// grab runs off the main thread; the tile stays an icon until
/// it lands. Explicit square frame — same overlap fix as the
/// image grid.
private struct VideoThumbView: View {
    let url: URL
    let size: CGFloat
    @State private var thumb: UIImage?

    var body: some View {
        ZStack {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            let image = await Task.detached { () -> UIImage? in
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                guard let cg = try? generator.copyCGImage(
                    at: CMTime(seconds: 0.5, preferredTimescale: 600),
                    actualTime: nil
                ) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if !Task.isCancelled {
                thumb = image
            }
        }
    }
}

/// Shared video-download progress. A class, so the URLSession
/// delegate callback — which captures a reference — actually
/// moves the UI; a struct copy would not.
final class VideoDownloadProgress: ObservableObject {
    @Published var fraction: Double?
}

/// Full-screen video viewing window: tap a thumbnail to watch,
/// download from here. The player is created on appear and torn
/// down on disappear so nothing keeps playing behind the sheet.
private struct VideoViewerView: View {
    let url: URL
    let quality: String?
    let isDownloading: Bool
    @ObservedObject var progress: VideoDownloadProgress
    let onDownload: () -> Void
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if let quality {
                        Text(quality)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Button("关闭", action: onClose)
                        .foregroundColor(.white)
                }
                .padding(16)
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    Spacer()
                }
                VStack(spacing: 8) {
                    if isDownloading {
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                                .tint(.white)
                            Text("\(Int(fraction * 100))%")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    } else {
                        HStack {
                            Spacer()
                            Button("下载") {
                                onDownload()
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
