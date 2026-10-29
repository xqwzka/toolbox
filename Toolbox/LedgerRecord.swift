import Foundation
import SwiftData

/// One income or expense record, stored only on-device via SwiftData.
/// No account, no sync, no network: deleting the app deletes the data.
///
/// Currency: `amount` is always the amount as entered, in
/// `currency`. Totals and charts use `amountCNY` so a book with
/// mixed currencies still sums in one unit (RMB). Both fields are
/// optional so pre-currency records (nil) read as plain RMB: adding
/// an optional column is a lightweight migration, old rows keep
/// working with no data rewrite.
@Model
final class LedgerRecord {
    // No hand-written `id`: SwiftData models are Identifiable via
    // their persistentIdentifier, which is what ForEach uses below.
    var amount: Double
    var isIncome: Bool
    var category: String
    var date: Date
    var note: String
    /// "CNY" or "USD". nil (pre-currency rows) means CNY.
    var currency: String?
    /// RMB per 1 unit of `currency`, locked at entry time. Only
    /// meaningful for USD rows; nil means 1.0.
    var exchangeRate: Double?

    /// Currency code with the legacy default folded in.
    var currencyCode: String {
        currency ?? "CNY"
    }

    /// Symbol for the entry currency.
    var currencySymbol: String {
        currencyCode == "USD" ? "$" : "¥"
    }

    /// The record's value in RMB, for totals and charts.
    var amountCNY: Double {
        if currencyCode == "USD" {
            return amount * (exchangeRate ?? 1)
        }
        return amount
    }

    init(
        amount: Double,
        isIncome: Bool,
        category: String,
        date: Date,
        note: String,
        currency: String? = nil,
        exchangeRate: Double? = nil
    ) {
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.date = date
        self.note = note
        self.currency = currency
        self.exchangeRate = exchangeRate
    }
}
