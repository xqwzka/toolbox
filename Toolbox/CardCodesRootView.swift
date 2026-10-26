import SwiftUI
import SwiftData
import UIKit

/// Main screen: counts header, search, filter pills, and the
/// card-code list. Tapping a row is the core action: it copies
/// the code, marks it used, and stamps the copy time.
struct CardCodesRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CardCode.createdAt, order: .reverse) private var codes: [CardCode]

    @State private var searchText = ""
    @State private var filter: CodeFilter = .all
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportURL: URL?
    @State private var editingCode: CardCode?
    @State private var toastVisible = false
    @State private var toastText = "已复制，已标记为已使用"
    @State private var toastID = 0

    private var filteredCodes: [CardCode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return codes.filter { record in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .unused:
                matchesFilter = !record.isUsed
            case .used:
                matchesFilter = record.isUsed
            }
            if !matchesFilter {
                return false
            }
            if query.isEmpty {
                return true
            }
            return record.code.localizedCaseInsensitiveContains(query)
                || record.note.localizedCaseInsensitiveContains(query)
        }
    }

    private var totalCount: Int {
        codes.count
    }

    private var unusedCount: Int {
        codes.filter { !$0.isUsed }.count
    }

    private var usedCount: Int {
        codes.filter { $0.isUsed }.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    HeaderCountsView(total: totalCount, unused: unusedCount, used: usedCount)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    SearchFieldView(text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    FilterPillsView(filter: $filter)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    codeList
                }
                if toastVisible {
                    ToastView(text: toastText)
                        .padding(.bottom, 24)
                }
            }
            .background(CardTheme.background.ignoresSafeArea())
            .navigationTitle("卡密管家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prepareExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(
                TextFilePicker(isPresented: $showingImporter) { urls in
                    if let url = urls.first {
                        importTextFile(url)
                    }
                }
            )
            .background(
                ActivityView(isPresented: $showingExporter, url: exportURL)
            )
            .sheet(isPresented: $showingAdd) {
                AddCardView()
            }
            .sheet(item: $editingCode) { record in
                EditCardView(record: record)
            }
        }
    }

    private var codeList: some View {
        Group {
            if filteredCodes.isEmpty {
                CardEmptyStateView(isSearching: !searchText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredCodes) { record in
                        Button {
                            copy(record)
                        } label: {
                            CardRowView(record: record)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                context.delete(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            if record.isUsed {
                                Button {
                                    unmark(record)
                                } label: {
                                    Label("取消标记", systemImage: "xmark.circle")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingCode = record
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(CardTheme.accent)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func copy(_ record: CardCode) {
        UIPasteboard.general.string = record.code
        record.isUsed = true
        record.copiedAt = Date()
        showToast()
    }

    private func unmark(_ record: CardCode) {
        record.isUsed = false
        record.copiedAt = nil
    }

    /// Import a .txt file: one code per line, optionally
    /// `code|note` (or code,note / code，note, same as batch add).
    /// Existing codes and in-file duplicates are skipped.
    private func importTextFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            showToast("导入失败，读不到这个文件")
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        let existing = Set(codes.map(\.code))
        let parsed = parseBatch(text, existing: existing)
        for item in parsed.items {
            context.insert(CardCode(code: item.code, note: item.note))
        }
        if parsed.items.isEmpty {
            showToast("没有可导入的卡密")
        } else if parsed.skipped > 0 {
            showToast("导入 \(parsed.items.count) 条，跳过 \(parsed.skipped) 条重复")
        } else {
            showToast("导入 \(parsed.items.count) 条")
        }
    }

    /// Export all codes to a .txt file in the same one-per-line
    /// format import reads back, then open the share sheet so it
    /// can be saved to Files or sent elsewhere.
    private func prepareExport() {
        guard !codes.isEmpty else {
            showToast("暂无卡密可导出")
            return
        }
        let lines = codes.map { record in
            record.note.isEmpty ? record.code : "\(record.code)|\(record.note)"
        }
        let text = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("卡密导出.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showToast("导出失败，写不出文件")
            return
        }
        exportURL = url
        showingExporter = true
    }

    private func showToast(_ message: String = "已复制，已标记为已使用") {
        toastID += 1
        let currentID = toastID
        toastText = message
        toastVisible = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if toastID == currentID {
                toastVisible = false
            }
        }
    }
}

private struct HeaderCountsView: View {
    let total: Int
    let unused: Int
    let used: Int

    var body: some View {
        HStack(spacing: 0) {
            CountBlock(title: "共", value: "\(total) 张")
            CountBlock(title: "未使用", value: "\(unused)")
            CountBlock(title: "已使用", value: "\(used)")
        }
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct CountBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SearchFieldView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("搜索卡密或备注", text: $text)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FilterPillsView: View {
    @Binding var filter: CodeFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CodeFilter.allCases, id: \.self) { option in
                FilterPill(title: option.rawValue, isSelected: filter == option) {
                    filter = option
                }
            }
            Spacer()
        }
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let bgColor: Color = isSelected ? CardTheme.accent : Color.white
        let textColor: Color = isSelected ? Color.white : Color.primary
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(bgColor)
                .foregroundColor(textColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CardEmptyStateView: View {
    let isSearching: Bool

    var body: some View {
        let message: String = isSearching ? "没有匹配的卡密" : "暂无卡密，点右上角 + 添加"
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text(message)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
    }
}
