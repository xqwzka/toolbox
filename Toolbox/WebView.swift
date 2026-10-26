import SwiftUI
import WebKit

/// One ephemeral website data store for the whole app launch.
/// Page state (localStorage, form input, generated output) works
/// while the app is running and is wiped completely when the
/// process ends, because a non-persistent store keeps nothing
/// on disk. Nothing here is persisted on purpose.
private let ephemeralStore = WKWebsiteDataStore.nonPersistent()

/// Serves the app's Documents folder over loopback HTTP, started
/// once for the app's lifetime. A real http://127.0.0.1 origin
/// (instead of file://) gives each page a stable origin, so JS and
/// in-session localStorage behave like in Safari.
private enum LocalServer {
    private static var server: LocalHTTPServer?

    static func url(for fileName: String) throws -> URL {
        if server == nil {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let started = LocalHTTPServer(directory: documents)
            try started.start()
            server = started
        }
        guard let port = server?.port, port != 0 else {
            throw NSError(domain: "LocalWeb", code: 1, userInfo: [NSLocalizedDescriptionKey: "本地服务启动失败"])
        }
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(encoded)") else {
            throw NSError(domain: "LocalWeb", code: 2, userInfo: [NSLocalizedDescriptionKey: "本地地址无效"])
        }
        return url
    }
}

/// WKWebView wrapper that opens an imported file through the
/// loopback HTTP server, so relative links between imported pages
/// keep working and the page gets a real http origin.
struct LocalWebView: UIViewRepresentable {
    let fileName: String
    let loadError: Binding<String?>
    let downloadError: Binding<String?>
    let isLoading: Binding<Bool>

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ephemeralStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        do {
            let url = try LocalServer.url(for: fileName)
            webView.load(URLRequest(url: url))
        } catch {
            loadError.wrappedValue = error.localizedDescription
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(loadError: loadError, downloadError: downloadError, isLoading: isLoading)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
        weak var webView: WKWebView?
        private var loadError: Binding<String?>
        private var downloadError: Binding<String?>
        private var isLoading: Binding<Bool>
        private var pendingDestinations: [ObjectIdentifier: URL] = [:]

        init(loadError: Binding<String?>, downloadError: Binding<String?>, isLoading: Binding<Bool>) {
            self.loadError = loadError
            self.downloadError = downloadError
            self.isLoading = isLoading
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading.wrappedValue = false
            loadError.wrappedValue = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading.wrappedValue = false
            loadError.wrappedValue = error.localizedDescription
        }

        // MARK: - Downloads
        //
        // WKWebView does not handle downloads on its own: a page
        // that triggers a download (the generator builds a Blob
        // and clicks an <a download> link) gets nothing by
        // default — no file, no prompt — even though the page
        // itself shows a "downloaded" toast. Safari handles this
        // natively; here the app must take over the download:
        // route download navigations to WKDownload, save the
        // file into Documents, and offer it through the share
        // sheet so it can be stored in Files or sent elsewhere.

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: destination)
            pendingDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = pendingDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            guard let root = webView?.window?.rootViewController else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = webView?.bounds ?? .zero
            }
            topViewController(from: root).present(activity, animated: true)
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            pendingDestinations.removeValue(forKey: ObjectIdentifier(download))
            downloadError.wrappedValue = error.localizedDescription
        }

        private func topViewController(from root: UIViewController) -> UIViewController {
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let root = webView.window?.rootViewController else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            topViewController(from: root).present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let root = webView.window?.rootViewController else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
            topViewController(from: root).present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let root = webView.window?.rootViewController else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            topViewController(from: root).present(alert, animated: true)
        }
    }
}
