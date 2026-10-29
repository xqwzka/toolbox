import Foundation

func startOfMonth(_ date: Date) -> Date {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return Calendar.current.date(from: components) ?? date
}

func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
    Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: .month)
}

func monthTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy年M月"
    return formatter.string(from: date)
}

func dayTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 EEEE"
    return formatter.string(from: date)
}

func formatMoney(_ amount: Double) -> String {
    String(format: "¥%.2f", amount)
}

func formatSignedMoney(_ record: LedgerRecord) -> String {
    (record.isIncome ? "+" : "-") + record.currencySymbol + String(format: "%.2f", record.amount)
}

/// RMB equivalent line for foreign-currency rows, e.g. "≈¥90.00".
/// CNY rows return nil: there is nothing to convert.
func convertedMoneyText(_ record: LedgerRecord) -> String? {
    guard record.currencyCode == "USD" else { return nil }
    return "≈" + formatMoney(record.amountCNY)
}

func shiftMonth(_ date: Date, by months: Int) -> Date {
    Calendar.current.date(byAdding: .month, value: months, to: date) ?? date
}

func isToday(_ date: Date) -> Bool {
    Calendar.current.isDateInToday(date)
}

func shortDayTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter.string(from: date)
}
