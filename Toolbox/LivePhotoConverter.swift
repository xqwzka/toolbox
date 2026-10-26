import Foundation
import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Video -> Live Photo, for the download screen.
///
/// A Live Photo is a still image plus a short video saved in ONE
/// PHAssetCreationRequest. The still is the middle frame of the
/// chosen segment; the segment is capped at 3 seconds (the Live
/// Photo video length). The trimmed clip is re-encoded to H.264
/// .mov, then re-muxed with a QuickTime metadata track carrying
/// the content identifier and the still-image-time, so Photos
/// plays it seamlessly on long-press instead of treating it as
/// a separate photo plus video.

enum LivePhotoError: Error, LocalizedError {
    case noVideoTrack
    case exportFailed
    case noFrame
    case writerFailed
    case photoDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "这个视频没有视频轨"
        case .exportFailed:
            return "视频裁剪失败"
        case .noFrame:
            return "截取静态图失败"
        case .writerFailed:
            return "Live Photo 合成失败"
        case .photoDenied:
            return "没有相册权限"
        case .saveFailed:
            return "保存到相册失败"
        }
    }
}

func convertVideoToLivePhoto(sourceURL: URL, start: Double, duration: Double) async throws {
    let asset = AVURLAsset(url: sourceURL)
    let sourceDuration = try await asset.load(.duration).seconds
    let safeStart = min(max(0, start), max(0, sourceDuration - 0.1))
    let safeDuration = min(duration, 3.0, max(0.1, sourceDuration - safeStart))
    let trimmed = try await trimVideo(sourceURL: sourceURL, start: safeStart, duration: safeDuration)
    let stillData = try extractStillFrame(videoURL: trimmed, at: safeDuration / 2)
    let identifier = UUID().uuidString
    let finalVideo = try await addLivePhotoMetadata(
        videoURL: trimmed,
        stillTime: CMTime(seconds: safeDuration / 2, preferredTimescale: 600),
        identifier: identifier
    )
    try await saveLivePhoto(photoData: stillData, videoURL: finalVideo)
}

/// Cut a segment and normalize it to an H.264 .mov (Live Photos
/// want QuickTime movie format; re-encoding also fixes HEVC and
/// other codecs the source may use).
private func trimVideo(sourceURL: URL, start: Double, duration: Double) async throws -> URL {
    let asset = AVURLAsset(url: sourceURL)
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
        throw LivePhotoError.exportFailed
    }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    session.outputURL = outputURL
    session.outputFileType = .mov
    session.timeRange = CMTimeRange(
        start: CMTime(seconds: start, preferredTimescale: 600),
        duration: CMTime(seconds: duration, preferredTimescale: 600)
    )
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        session.exportAsynchronously {
            continuation.resume()
        }
    }
    guard session.status == .completed else {
        throw session.error ?? LivePhotoError.exportFailed
    }
    return outputURL
}

/// One frame as JPEG data, with the track transform applied so
/// portrait videos do not come out sideways.
private func extractStillFrame(videoURL: URL, at seconds: Double) throws -> Data {
    let asset = AVURLAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let cgImage = try generator.copyCGImage(
        at: CMTime(seconds: seconds, preferredTimescale: 600),
        actualTime: nil
    )
    guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) else {
        throw LivePhotoError.noFrame
    }
    return data
}

/// Re-mux the trimmed clip with a QuickTime metadata track:
/// content-identifier at time zero, still-image-time at the still
/// frame. Video and audio tracks pass through untouched (nil
/// output settings). Metadata is best-effort: even if the track
/// is dropped, the single-request save below still pairs the
/// photo and video into one asset.
private func addLivePhotoMetadata(videoURL: URL, stillTime: CMTime, identifier: String) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw LivePhotoError.noVideoTrack
    }
    let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
        throw LivePhotoError.writerFailed
    }
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    videoInput.expectsMediaDataInRealTime = false
    var audioInput: AVAssetWriterInput?
    if audioTrack != nil {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        input.expectsMediaDataInRealTime = false
        audioInput = input
    }
    let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil)
    metadataInput.expectsMediaDataInRealTime = false
    let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
    guard writer.canAdd(videoInput) else {
        throw LivePhotoError.writerFailed
    }
    writer.add(videoInput)
    if let audioInput, writer.canAdd(audioInput) {
        writer.add(audioInput)
    }
    guard writer.canAdd(metadataInput) else {
        throw LivePhotoError.writerFailed
    }
    writer.add(metadataInput)
    guard let reader = try? AVAssetReader(asset: asset) else {
        throw LivePhotoError.writerFailed
    }
    let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    reader.add(videoOutput)
    var audioOutput: AVAssetReaderTrackOutput?
    if let audioTrack {
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(output)
        audioOutput = output
    }
    guard reader.startReading() else {
        throw LivePhotoError.writerFailed
    }
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    func metadataItem(key: String, value: (NSCopying & NSObjectProtocol)) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = key as NSString
        item.value = value
        return item
    }
    let identifierGroup = AVTimedMetadataGroup(
        items: [metadataItem(key: "com.apple.quicktime.content-identifier", value: identifier as NSString)],
        timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 0.1, preferredTimescale: 600))
    )
    let stillGroup = AVTimedMetadataGroup(
        items: [metadataItem(key: "com.apple.quicktime.still-image-time", value: NSValue(time: stillTime))],
        timeRange: CMTimeRange(start: stillTime, duration: CMTime(seconds: 0.1, preferredTimescale: 600))
    )
    _ = metadataAdaptor.append(identifierGroup)
    _ = metadataAdaptor.append(stillGroup)
    let writingQueue = DispatchQueue(label: "livephoto.writer")
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        let group = DispatchGroup()
        group.enter()
        videoInput.requestMediaDataWhenReady(on: writingQueue) {
            while videoInput.isReadyForMoreMediaData {
                guard let buffer = videoOutput.copyNextSampleBuffer() else {
                    videoInput.markAsFinished()
                    group.leave()
                    break
                }
                videoInput.append(buffer)
            }
        }
        if let audioInput, let audioOutput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: writingQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let buffer = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        break
                    }
                    audioInput.append(buffer)
                }
            }
        }
        group.notify(queue: writingQueue) {
            if reader.status == .failed {
                continuation.resume(throwing: reader.error ?? LivePhotoError.writerFailed)
                return
            }
            metadataInput.markAsFinished()
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: writer.error ?? LivePhotoError.writerFailed)
                }
            }
        }
    }
}

/// The pairing itself: photo and video in ONE creation request,
/// which is what makes Photos treat them as a single Live Photo
/// instead of two separate assets.
private func saveLivePhoto(photoData: Data, videoURL: URL) async throws {
    guard await requestPhotoAddAccess() else {
        throw LivePhotoError.photoDenied
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: photoData, options: nil)
            request.addResource(with: .video, fileURL: videoURL, options: nil)
        }) { success, error in
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: error ?? LivePhotoError.saveFailed)
            }
        }
    }
}

// MARK: - Pickers (same host pattern as the other UIKit pickers)

/// Pick a video from Photos without needing full library access:
/// PHPicker only hands over the one video the user chose.
struct PhotoVideoPicker: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> PhotoVideoPickerHostViewController {
        PhotoVideoPickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: PhotoVideoPickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class PhotoVideoPickerHostViewController: UIViewController, PHPickerViewControllerDelegate {
    var isPresented: Binding<Bool>
    var onPick: (URL) -> Void

    init(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) {
        self.isPresented = isPresented
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePresentation() {
        if isPresented.wrappedValue {
            guard presentedViewController == nil else { return }
            var configuration = PHPickerConfiguration()
            configuration.filter = .videos
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        } else if presentedViewController != nil {
            dismiss(animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        isPresented.wrappedValue = false
        guard let result = results.first else { return }
        let provider = result.itemProvider
        let typeID = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .video) == true })
            ?? UTType.movie.identifier
        provider.loadFileRepresentation(forTypeIdentifier: typeID) { [weak self] url, error in
            guard let url, error == nil else { return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async {
                    self?.onPick(dest)
                }
            } catch {
                // The provider URL may already be usable; hand it
                // over directly rather than failing the pick.
                DispatchQueue.main.async {
                    self?.onPick(url)
                }
            }
        }
    }
}

/// Pick a video file from Files (.mov / .mp4).
struct VideoFilePicker: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> VideoFilePickerHostViewController {
        VideoFilePickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: VideoFilePickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class VideoFilePickerHostViewController: UIViewController, UIDocumentPickerDelegate {
    var isPresented: Binding<Bool>
    var onPick: (URL) -> Void

    init(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) {
        self.isPresented = isPresented
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePresentation() {
        if isPresented.wrappedValue {
            guard presentedViewController == nil else { return }
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [UTType.movie, UTType.mpeg4Movie],
                asCopy: true
            )
            picker.delegate = self
            picker.allowsMultipleSelection = false
            present(picker, animated: true)
        } else if presentedViewController != nil {
            dismiss(animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        isPresented.wrappedValue = false
        if let url = urls.first {
            onPick(url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        isPresented.wrappedValue = false
    }
}
