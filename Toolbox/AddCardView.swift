import SwiftUI
import SwiftData

/// Add sheet with a segmented switch between single entry and
/// batch import. Single: code is required, note is optional.
/// Batch: one code per line, optionally followed by a note after
/// the first | or , or ，.
struct AddCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CardCode.createdAt, order: .reverse) private var existingCodes: [CardCode]

    @State private var mode: AddMode = .single
    @State private var code = ""
    @State private var note = ""
    @State private var batchText = ""

    private var existingSet: Set<String> {
        Set(existingCodes.map { $0.code })
    }

    private var parsedBatch: (items: [BatchItem], skipped: Int) {
        parseBatch(batchText, existing: existingSet)
    }

    private var singleSaveDisabled: Bool {
        code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("添加方式", selection: $mode) {
                    Text("单条").tag(AddMode.single)
                    Text("批量").tag(AddMode.batch)
                }
                .pickerStyle(.segmented)
                if mode == .single {
                    SingleFormView(code: $code, note: $note)
                    Spacer()
                    SaveButton(title: "保存", disabled: singleSaveDisabled) {
                        saveSingle()
                    }
                } else {
                    BatchFormView(text: $batchText, newCount: parsedBatch.items.count, skipped: parsedBatch.skipped)
                    Spacer()
                    SaveButton(title: "导入", disabled: parsedBatch.items.isEmpty) {
                        importBatch()
                    }
                }
            }
            .padding(16)
            .background(CardTheme.background.ignoresSafeArea())
            .navigationTitle("添加卡密")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func saveSingle() {
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        guard !trimmedCode.isEmpty else { return }
        context.insert(CardCode(code: trimmedCode, note: trimmedNote))
        dismiss()
    }

    private func importBatch() {
        for item in parsedBatch.items {
            context.insert(CardCode(code: item.code, note: item.note))
        }
        dismiss()
    }
}

enum AddMode {
    case single
    case batch
}

/// Code + note fields shared by single-add and edit.
struct SingleFormView: View {
    @Binding var code: String
    @Binding var note: String

    var body: some View {
        VStack(spacing: 12) {
            TextField("卡密", text: $code)
                .font(.system(.body, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            TextField("备注，如：Steam、京东，用在哪", text: $note)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BatchFormView: View {
    @Binding var text: String
    let newCount: Int
    let skipped: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if text.isEmpty {
                    Text("每行一条卡密，可加备注：\nABCD-1234 | Steam\nEFGH-5678，京东")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
            Text("将导入 \(newCount) 条新卡密" + (skipped > 0 ? "，跳过 \(skipped) 条重复" : ""))
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

private struct SaveButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        let bgColor: Color = disabled ? CardTheme.accent.opacity(0.4) : CardTheme.accent
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled)
    }
}
