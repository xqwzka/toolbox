import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Output screen for the software selected at the top of the
/// editor — no format switch here anymore. Shows that side's
/// generated config with copy, share-as-file, and unified
/// import (paste or file — via a UIKit document picker, since
/// SwiftUI.fileImporter never completes on the user's device).
/// Import auto-detects the format: YAML replaces the Clash
/// side, .conf replaces the Shadowrocket side; the other side
/// is left untouched.
struct ProxyOutputView: View {
    @Binding var draft: ConfigData
    let software: ProxySoftware
    let configName: String
    let onImportClash: (ConfigData) -> Void
    let onImportShadowrocket: (ConfigData) -> Void

    @State private var clashFilename = "clash-config"
    @State private var srFilename = "shadowrocket-config"
    @State private var shareItems: [Any]?
    @State private var showingImport = false
    @State private var copied = false

    private var generated: ProxyGeneratedOutput {
        software == .shadowrocket ? proxyGenerateShadowrocket(draft) : proxyGenerateClash(draft)
    }

    private var activeText: String { generated.text }
    private var activeWarnings: [String] { generated.warnings }
    private var activeFilename: String { software == .shadowrocket ? srFilename : clashFilename }
    private var activeExtension: String { software == .shadowrocket ? "conf" : "yaml" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("文件名", text: software == .shadowrocket ? $srFilename : $clashFilename)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text(".\(activeExtension)")
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

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
                Button("导入配置") { showingImport = true }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(configName + " · " + (software == .shadowrocket ? "Shadowrocket 配置预览" : "Clash / Mihomo 配置预览"))
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
            ProxyImportSheet { imported, side in
                if side == .shadowrocket {
                    onImportShadowrocket(imported)
                } else {
                    onImportClash(imported)
                }
                showingImport = false
            }
        }
        .alert("已复制", isPresented: $copied) {
            Button("好", role: .cancel) {}
        }
    }

    private func share() {
        let base = activeFilename.trimmingCharacters(in: .whitespaces)
        let name = base.isEmpty ? (software == .shadowrocket ? "shadowrocket-config" : "clash-config") : base
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

/// Shared by the editor and the output page. Detects the
/// format from the text: [Section] headers mean Shadowrocket
/// .conf, anything else is tried as Clash YAML. The confirm
/// dialog names the side that will be replaced.
struct ProxyImportSheet: View {
    let onConfirm: (ConfigData, ProxySoftware) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importText = ""
    @State private var importError = ""
    @State private var pendingImport: PendingImport?
    @State private var showingFilePicker = false

    private struct PendingImport {
        var imported: ProxyImportedConfig
        var side: ProxySoftware
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $importText)
                    .frame(minHeight: 300)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("粘贴 Clash YAML 或 Shadowrocket .conf，或从文件选择。识别格式后替换对应一侧的配置，另一侧不受影响。YAML 节点不写回订阅，改为单个节点；.conf 的策略组订阅地址会按域名新建订阅。")
                    .font(.caption)
                    .foregroundColor(.gray)
                if !importError.isEmpty {
                    Text(importError).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle("导入配置")
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
                ProxyImportFilePicker { data in
                    showingFilePicker = false
                    importText = String(data: data, encoding: .utf8) ?? ""
                    parseImport(importText)
                }
            }
            .alert(pendingImport?.side == .shadowrocket ? "确认替换 Shadowrocket 配置？" : "确认替换 Clash 配置？", isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )) {
                Button("取消", role: .cancel) { pendingImport = nil }
                Button("替换", role: .destructive) {
                    if let pendingImport {
                        onConfirm(pendingImport.imported.config, pendingImport.side)
                    }
                    pendingImport = nil
                }
            } message: {
                if let pendingImport {
                    let counts = pendingImport.imported.config
                    let warns = pendingImport.imported.warnings.isEmpty
                        ? ""
                        : "\n警告：\n" + pendingImport.imported.warnings.joined(separator: "\n")
                    Text("将替换为：\(counts.subscriptions.count) 订阅、\(counts.nodeLinks.count) 单节点、\(counts.strategies.count) 策略、\(counts.providers.count) 规则集、\(counts.rules.count) 分流规则。\(warns)")
                }
            }
        }
    }

    private func parseImport(_ text: String) {
        do {
            let side = proxyDetectImportFormat(text)
            let imported = side == .shadowrocket
                ? try proxyImportedSRState(text)
                : try proxyImportedState(text)
            pendingImport = PendingImport(imported: imported, side: side)
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

/// Own config picker: the app's DocumentPicker hardcodes
/// UTType.html, and SwiftUI.fileImporter never completes on
/// the user's device, so this presenter takes yaml/yml/conf/text.
private struct ProxyImportFilePicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [
            UTType(filenameExtension: "yaml"),
            UTType(filenameExtension: "yml"),
            UTType(filenameExtension: "conf"),
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
