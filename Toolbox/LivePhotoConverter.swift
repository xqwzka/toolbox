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
/// .mov and saved directly: the single-request pairing is what
/// makes Photos treat the two as one Live Photo. An earlier
/// build re-muxed the clip with a QuickTime metadata track
/// (content-identifier + still-image-time) for seamless
/// playback, but that step crashed on-device, so it was removed;
/// if long-press playback jumps from the still to the video
/// start instead of playing seamlessly, that step is the thing
/// to revisit.

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
    try await saveLivePhoto(photoData: stillData, videoURL: trimmed)
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
