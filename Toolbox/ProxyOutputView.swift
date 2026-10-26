import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Output screen: Clash YAML and Shadowrocket .conf previews
/// generated from the editor draft, with copy, share-as-file,
/// and YAML import (paste or file — via a UIKit document
/// picker, since SwiftUI.fileImporter never completes on the
/// user's device). Import replaces the whole draft after a
/// confirmation alert.
struct ProxyOutputView: View {
    @Binding var draft: ConfigData
    let configName: String

    @State private var kind = 0
    @State private var clashFilename = "clash-config"
    @State private var srFilename = "shadowrocket-config"
    @State private var shareItems: [Any]?
    @State private var showingImport = false
    @State private var copied = false

    private var clash: ProxyGeneratedOutput { proxyGenerateClash(draft) }
    private var shadowrocket: ProxyGeneratedOutput { proxyGenerateShadowrocket(draft) }

    private var activeText: String { kind == 0 ? clash.text : shadowrocket.text }
    private var activeWarnings: [String] { kind == 0 ? clash.warnings : shadowrocket.warnings }
    private var activeFilename: String { kind == 0 ? clashFilename : srFilename }
    private var activeExtension: String { kind == 0 ? "yaml" : "conf" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("输出格式", selection: $kind) {
                Text("Clash YAML").tag(0)
                Text("Shadowrocket").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            HStack {
                TextField("文件名", text: kind == 0 ? $clashFilename : $srFilename)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text(".\(activeExtension)")
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)

            if !activeWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeWarnings, id: \.self) { warning in
                        Text("⚠ \(warning)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            ScrollView {
                Text(activeText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            HStack(spacing: 12) {
                Button("复制") {
                    UIPasteboard.general.string = activeText
                    copied = true
                }
                .buttonStyle(.bordered)
                Button("分享文件") { share() }
                    .buttonStyle(.borderedProminent)
                Button("导入 YAML") { showingImport = true }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(configName + " · 生成结果")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let shareItems {
                ProxyShareSheet(items: shareItems)
            }
        }
        .sheet(isPresented: $showingImport) {
            ProxyImportSheet { imported in
                draft = imported
                showingImport = false
            }
        }
        .alert("已复制", isPresented: $copied) {
            Button("好", role: .cancel) {}
        }
    }

    private func share() {
        let base = activeFilename.trimmingCharacters(in: .whitespaces)
        let name = base.isEmpty ? (kind == 0 ? "clash-config" : "shadowrocket-config") : base
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(activeExtension)
        if (try? activeText.write(to: url, atomically: true, encoding: .utf8)) != nil {
            shareItems = [url]
        } else {
            shareItems = [activeText]
        }
    }

}

private struct ProxyImportSheet: View {
    let onConfirm: (ConfigData) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importText = ""
    @State private var importError = ""
    @State private var pendingImport: ProxyImportedConfig?
    @State private var showingFilePicker = false

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $importText)
                    .frame(minHeight: 300)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("粘贴 Clash YAML，或从文件选择。解析后需确认才会替换当前配置；节点不写回订阅，改为单个节点。")
                    .font(.caption)
                    .foregroundColor(.gray)
                if !importError.isEmpty {
                    Text(importError).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle("导入 Clash YAML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("从文件选择") { showingFilePicker = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("解析") { parseImport(importText) }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                ProxyYamlPicker { data in
                    showingFilePicker = false
                    importText = String(data: data, encoding: .utf8) ?? ""
                    parseImport(importText)
                }
            }
            .alert("确认替换当前配置？", isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )) {
                Button("取消", role: .cancel) { pendingImport = nil }
                Button("替换", role: .destructive) {
                    if let pendingImport {
                        onConfirm(pendingImport.config)
                    }
                    pendingImport = nil
                }
            } message: {
                if let pendingImport {
                    let counts = pendingImport.config
                    let warns = pendingImport.warnings.isEmpty
                        ? ""
                        : "\n警告：\n" + pendingImport.warnings.joined(separator: "\n")
                    Text("将替换为：\(counts.subscriptions.count) 订阅、\(counts.nodeLinks.count) 单节点、\(counts.strategies.count) 策略、\(counts.providers.count) 规则集、\(counts.rules.count) 分流规则。\(warns)")
                }
            }
        }
    }

    private func parseImport(_ text: String) {
        do {
            pendingImport = try proxyImportedState(text)
            importError = ""
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ProxyShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Own YAML picker: the app's DocumentPicker hardcodes
/// UTType.html, and SwiftUI.fileImporter never completes on
/// the user's device, so this presenter takes yaml/yml/text.
private struct ProxyYamlPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [
            UTType(filenameExtension: "yaml"),
            UTType(filenameExtension: "yml"),
            UTType.plainText
        ].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Data) -> Void

        init(onPick: @escaping (Data) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
            onPick(data)
        }
    }
}
