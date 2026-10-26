import SwiftUI

/// File list screen: shows the HTML files imported into Documents.
/// Imported files persist across launches; only page state resets.
/// Pages are served over a loopback HTTP server instead of file://
/// URLs. Import runs on a background queue. File picking goes
/// through the UIKit document picker (see DocumentPicker.swift):
/// SwiftUI's .fileImporter never completed in this app — after
/// selecting a file and tapping 打开 the picker stayed open and
/// its completion handler never ran.
struct WebRootView: View {
    @State private var files: [String] = []
    @State private var showImporter = false
    @State private var viewerFile: String?
    @State private var importError: String?
    @State private var importNotice: String?
    @State private var isImporting = false

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView(
                        "还没有导入的网页",
                        systemImage: "doc.text",
                        description: Text("点右上角的 + 导入 .html 文件，导入后点文件名即可在 App 内打开。")
                    )
                } else {
                    List {
                        Section {
                            ForEach(files, id: \.self) { name in
                                Button {
                                    viewerFile = name
                                } label: {
                                    Label(name, systemImage: "doc.text")
                                }
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
            }
            .navigationTitle("本地网页")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
            }
            .background(
                DocumentPickerPresenter(isPresented: $showImporter) { urls in
                    startImport(urls)
                }
            )
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("已导入", isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importNotice ?? "")
            }
            .onOpenURL { url in
                openExternalFile(url)
            }
            .fullScreenCover(isPresented: Binding(
                get: { viewerFile != nil },
                set: { if !$0 { viewerFile = nil } }
            )) {
                if let name = viewerFile {
                    WebViewerScreen(fileName: name) {
                        viewerFile = nil
                    }
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在导入…")
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil
        )) ?? []
        files = items
            .filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Starts an import on a background queue and reports back on
    /// the main thread. Import used to run synchronously in the
    /// picker completion on the main thread, so coordinating an
    /// iCloud file that was not downloaded yet froze the UI: the
    /// picker stayed open with no feedback. Now the picker
    /// dismisses immediately, a progress overlay shows, and the
    /// result arrives as an alert.
    private func startImport(_ urls: [URL], openFirst: Bool = false) {
        guard !urls.isEmpty else { return }
        isImporting = true
        let docs = documentsURL
        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            var imported: [String] = []
            for url in urls {
                if let message = Self.copyFileIntoDocuments(url, to: docs) {
                    failures.append("\(url.lastPathComponent)：\(message)")
                } else {
                    imported.append(url.lastPathComponent)
                }
            }
            DispatchQueue.main.async {
                self.isImporting = false
                self.refresh()
                if !failures.isEmpty {
                    self.importError = failures.joined(separator: "\n")
                } else if !imported.isEmpty {
                    self.importNotice = "已导入 \(imported.count) 个文件，点文件名即可打开。"
                }
                if openFirst, let first = imported.first {
                    self.viewerFile = first
                }
            }
        }
    }

    /// Copies one picked or externally opened file into Documents.
    /// Coordinated read: for iCloud files that are not downloaded
    /// yet, the coordinator downloads the file before handing it
    /// to the accessor. A plain copyItem skips this and fails.
    /// Returns an error message on failure, nil on success.
    private static func copyFileIntoDocuments(_ url: URL, to documentsURL: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let dest = documentsURL.appendingPathComponent(url.lastPathComponent)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: .forUploading,
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: coordinatedURL, to: dest)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError {
            return error.localizedDescription
        }
        return nil
    }

    /// Handles a file opened from outside the app (Files app, share
    /// sheet, "Open in…"): import it in the background and open it
    /// when the copy finishes.
    private func openExternalFile(_ url: URL) {
        guard ["html", "htm"].contains(url.pathExtension.lowercased()) else {
            importError = "只支持 .html 文件"
            return
        }
        startImport([url], openFirst: true)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let url = documentsURL.appendingPathComponent(files[index])
            try? FileManager.default.removeItem(at: url)
        }
        refresh()
    }
}

/// Viewer screen: a top bar with a 返回 button and the file name,
/// and the web view below it.
struct WebViewerScreen: View {
    let fileName: String
    let onClose: () -> Void

    @State private var loadError: String?
    @State private var downloadError: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                LocalWebView(
                    fileName: fileName,
                    loadError: $loadError,
                    downloadError: $downloadError,
                    isLoading: $isLoading
                )
                if isLoading {
                    ProgressView()
                }
            }
            .alert("打开失败", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(loadError ?? "")
            }
            .alert("下载失败", isPresented: Binding(
                get: { downloadError != nil },
                set: { if !$0 { downloadError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(downloadError ?? "")
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回", action: onClose)
                }
            }
        }
    }
}
