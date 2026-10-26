import Foundation
import SwiftData

/// One activation code. Identity comes from SwiftData's
/// persistentIdentifier, so no hand-written id field is needed.
@Model
final class CardCode {
    var code: String
    var note: String
    var isUsed: Bool
    var copiedAt: Date?
    var createdAt: Date

    init(code: String, note: String = "", isUsed: Bool = false, copiedAt: Date? = nil, createdAt: Date = Date()) {
        self.code = code
        self.note = note
        self.isUsed = isUsed
        self.copiedAt = copiedAt
        self.createdAt = createdAt
    }
}
