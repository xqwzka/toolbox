import Foundation
import SwiftData
import UIKit

/// One imported image. The image bytes live as a file under
/// Documents/images, never in the SwiftData store itself: a
/// photo library can grow large, and stuffing raw image data
/// into the model would bloat the database and slow every
/// query. The record only carries the file name and the
/// import time; deleting the record deletes its file too.
/// Identity comes from SwiftData's persistentIdentifier.
@Model
final class StoredImage {
    var fileName: String
    var createdAt: Date

    init(fileName: String, createdAt: Date = Date()) {
        self.fileName = fileName
        self.createdAt = createdAt
    }

    /// Documents/images, created on first save.
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
    }

    var fileURL: URL {
        Self.directory.appendingPathComponent(fileName)
    }

    var image: UIImage? {
        UIImage(contentsOfFile: fileURL.path)
    }

    /// Write raw image data to a new file and return its record.
    /// Returns nil when the data is not an image or cannot be
    /// written; the caller counts only non-nil returns as
    /// imported. The raw bytes are kept as-is (HEIC stays HEIC),
    /// so the file on disk is exactly what was imported.
    static func saveImageData(_ data: Data, ext: String) -> StoredImage? {
        guard UIImage(data: data) != nil else { return nil }
        let dir = directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let cleanExt = ext.trimmingCharacters(in: .whitespaces).lowercased()
        let fileName = UUID().uuidString + "." + (cleanExt.isEmpty ? "jpg" : cleanExt)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return StoredImage(fileName: fileName)
    }

    static func deleteFile(named fileName: String) {
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
