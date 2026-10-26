import SwiftUI

/// One card-code row: white rounded card on the gray list
/// background. The code uses a monospaced font and wraps to at
/// most two lines; the note and copy time sit below it.
struct CardRowView: View {
    let record: CardCode

    var body: some View {
        let displayCode: String = record.code
        let pillText: String = record.isUsed ? "已使用" : "未使用"
        let pillBackground: Color = record.isUsed ? Color.gray.opacity(0.15) : Color.green.opacity(0.15)
        let pillColor: Color = record.isUsed ? Color.gray : Color.green
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(displayCode)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                Spacer()
                Text(pillText)
                    .font(.caption)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(pillBackground)
                    .foregroundColor(pillColor)
                    .clipShape(Capsule())
            }
            if !record.note.isEmpty {
                Text(record.note)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            if record.isUsed, let copiedAt = record.copiedAt {
                Text(copiedText(copiedAt))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
