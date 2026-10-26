import Foundation
import SwiftUI

/// Shared look: light-gray screen background, white cards,
/// teal accent (matches the app icon). All layouts use flexible
/// widths, never fixed screen widths, so the UI adapts to every
/// iPhone width.
enum CardTheme {
    static let background: Color = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let fieldBackground: Color = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let accent: Color = Color(red: 0.05, green: 0.58, blue: 0.55)
}

/// Filter pills on the main list.
enum CodeFilter: String, CaseIterable {
    case all = "全部"
    case unused = "未使用"
    case used = "已使用"
}

/// Hide a code: bullets plus the last 4 characters. A code of
/// 4 characters or fewer is shown as bullets only.
func maskedCode(_ code: String) -> String {
    if code.count <= 4 {
        return String(repeating: "•", count: code.count)
    }
    return "••••" + String(code.suffix(4))
}

/// "已复制 · 10月25日 22:10" style timestamp.
func copiedText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return "已复制 · " + formatter.string(from: date)
}

/// One parsed batch line: a code plus an optional note.
struct BatchItem {
    let code: String
    let note: String
}

/// Parse batch input, one code per line. A line may be just a code,
/// or code + note separated by the first | or , or ，.
/// Trims whitespace, skips empty lines, skips codes that already
/// exist and duplicates inside the batch. Returns the new items
/// and how many non-empty lines were skipped.
func parseBatch(_ text: String, existing: Set<String>) -> (items: [BatchItem], skipped: Int) {
    var items: [BatchItem] = []
    var seen: Set<String> = []
    var nonEmptyLines = 0
    let separators: Set<Character> = ["|", ",", "，"]
    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            continue
        }
        nonEmptyLines += 1
        let code: String
        let note: String
        if let sepIndex = line.firstIndex(where: { separators.contains($0) }) {
            code = String(line[..<sepIndex]).trimmingCharacters(in: .whitespaces)
            let after = line.index(after: sepIndex)
            note = String(line[after...]).trimmingCharacters(in: .whitespaces)
        } else {
            code = line
            note = ""
        }
        if code.isEmpty || existing.contains(code) || seen.contains(code) {
            continue
        }
        seen.insert(code)
        items.append(BatchItem(code: code, note: note))
    }
    return (items, nonEmptyLines - items.count)
}
