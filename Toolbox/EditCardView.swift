import SwiftUI

/// Edit sheet for one existing code: code + note only.
/// Saving never changes the used status or the copy time.
struct EditCardView: View {
    @Environment(\.dismiss) private var dismiss

    let record: CardCode

    @State private var code: String
    @State private var note: String

    init(record: CardCode) {
        self.record = record
        _code = State(initialValue: record.code)
        _note = State(initialValue: record.note)
    }

    private var saveDisabled: Bool {
        code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let saveBg: Color = saveDisabled ? CardTheme.accent.opacity(0.4) : CardTheme.accent
        NavigationStack {
            VStack(spacing: 16) {
                SingleFormView(code: $code, note: $note)
                Spacer()
                Button {
                    save()
                } label: {
                    Text("保存")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(saveBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(saveDisabled)
            }
            .padding(16)
            .background(CardTheme.background.ignoresSafeArea())
            .navigationTitle("编辑卡密")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        guard !trimmedCode.isEmpty else { return }
        record.code = trimmedCode
        record.note = trimmedNote
        dismiss()
    }
}
