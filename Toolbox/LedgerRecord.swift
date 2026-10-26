import Foundation
import SwiftData

/// One income or expense record, stored only on-device via SwiftData.
/// No account, no sync, no network: deleting the app deletes the data.
@Model
final class LedgerRecord {
    // No hand-written `id`: SwiftData models are Identifiable via
    // their persistentIdentifier, which is what ForEach uses below.
    var amount: Double
    var isIncome: Bool
    var category: String
    var date: Date
    var note: String

    init(
        amount: Double,
        isIncome: Bool,
        category: String,
        date: Date,
        note: String
    ) {
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.date = date
        self.note = note
    }
}
