import Foundation
import Photos
import AVFoundation
import UIKit

/// Downloading and saving parsed media. Everything saves to the
/// photo library by default; callers fall back to the share sheet
/// when saving is denied or fails.

enum DownloadError: Error, LocalizedError {
    case network
    case photoDenied
    case photoFailed
    case muxFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .network:
            return "下载失败，网络错误"
        case .photoDenied:
            return "没有相册权限"
        case .photoFailed:
            return "保存到相册失败"
        case .muxFailed:
            return "音画合成失败"
        case .invalidImage:
            return "图片数据损坏"
        }
    }
}

/// Download a remote file to a stable temp path (URLSession's own
/// temp file disappears after the call, so copy it first).
func downloadFile(from url: URL, defaultExtension: String = "mp4") async throws -> URL {
    let tempURL: URL
    let response: URLResponse
    do {
        (tempURL, response) = try await URLSession.shared.download(from: url)
    } catch {
        throw DownloadError.network
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw DownloadError.network
    }
    let ext = url.pathExtension.isEmpty ? defaultExtension : url.pathExtension
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
    try FileManager.default.copyItem(at: tempURL, to: dest)
    return dest
}

/// Download with progress. URLSession's async download API
/// reports nothing while it runs, so video downloads looked
/// dead until they either saved or failed. The delegate
/// reports fractional progress; transport failures (no
/// response at all) surface as URLError so callers can retry
/// them, while HTTP errors surface as DownloadError.network
/// (retrying a 403 is pointless).
func downloadFileWithProgress(from url: URL, defaultExtension: String = "mp4", onProgress: ((Double) -> Void)? = nil) async throws -> URL {
    final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        var continuation: CheckedContinuation<URL, Error>?
        var onProgress: ((Double) -> Void)?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, code != 200 {
                continuation?.resume(throwing: DownloadError.network)
            } else {
                continuation?.resume(returning: location)
            }
            continuation = nil
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }

    let delegate = Delegate()
    delegate.onProgress = onProgress
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
    defer { session.finishTasksAndInvalidate() }
    let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        delegate.continuation = continuation
        session.downloadTask(with: url).resume()
    }
    let ext = url.pathExtension.isEmpty ? defaultExtension : url.pathExtension
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
    try FileManager.default.copyItem(at: tempURL, to: dest)
    return dest
}

func downloadData(from url: URL) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(from: url)
    } catch {
        throw DownloadError.network
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw DownloadError.network
    }
    return data
}

func requestPhotoAddAccess() async -> Bool {
    await withCheckedContinuation { continuation in
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            continuation.resume(returning: status == .authorized || status == .limited)
        }
    }
}

func saveVideoToPhotos(_ fileURL: URL) async throws {
    guard await requestPhotoAddAccess() else {
        throw DownloadError.photoDenied
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }) { success, error in
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: error ?? DownloadError.photoFailed)
            }
        }
    }
}

func saveImageDataToPhotos(_ data: Data) async throws {
    guard let image = UIImage(data: data) else {
        throw DownloadError.invalidImage
    }
    guard await requestPhotoAddAccess() else {
        throw DownloadError.photoDenied
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: error ?? DownloadError.photoFailed)
            }
        }
    }
}

/// Mux a video-only file and an audio-only file into one mp4.
/// This is what makes YouTube high quality work: no-key APIs only
/// serve split streams above 720p, so the app joins the best
/// avc1 video with the best mp4 audio on-device.
func muxVideo(videoURL: URL, audioURL: URL) async throws -> URL {
    let videoAsset = AVURLAsset(url: videoURL)
    let audioAsset = AVURLAsset(url: audioURL)
    guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
          let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
        throw DownloadError.muxFailed
    }
    let videoDuration = try await videoAsset.load(.duration)
    let audioDuration = try await audioAsset.load(.duration)
    let composition = AVMutableComposition()
    guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
          let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw DownloadError.muxFailed
    }
    try videoCompositionTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: videoTrack,
        at: .zero
    )
    try audioCompositionTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration)),
        of: audioTrack,
        at: .zero
    )
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw DownloadError.muxFailed
    }
    session.outputURL = output
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        session.exportAsynchronously {
            continuation.resume()
        }
    }
    guard session.status == .completed else {
        throw session.error ?? DownloadError.muxFailed
    }
    return output
}
