import Foundation
import Network

/// Tiny loopback-only HTTP server that serves one directory to the
/// in-app WKWebView. It binds to the loopback interface only, so
/// nothing on the network can reach it. No external dependencies.
final class LocalHTTPServer {
    private let directory: URL
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "localweb.http")
    private(set) var port: UInt16 = 0

    init(directory: URL) {
        self.directory = directory
    }

    /// Starts listening and blocks (up to 5 seconds) until the
    /// listener is ready, so `port` is valid on return.
    func start() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params, on: 0)
        let ready = DispatchSemaphore(value: 0)
        var startError: NWError?
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = listener.port?.rawValue ?? 0
                ready.signal()
            case .failed(let error):
                startError = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw NSError(domain: "LocalWeb", code: 3, userInfo: [NSLocalizedDescriptionKey: "本地服务启动超时"])
        }
        if let error = startError {
            throw error
        }
        guard port != 0 else {
            throw NSError(domain: "LocalWeb", code: 4, userInfo: [NSLocalizedDescriptionKey: "本地服务没有拿到端口"])
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveRequest(on: connection, buffer: Data())
            }
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            var combined = buffer
            combined.append(data)
            if let headerEnd = combined.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(data: combined[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                self.respond(to: header, on: connection)
            } else if isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: combined)
            }
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let requestLine = header.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        var rawPath = parts.count > 1 ? String(parts[1]) : "/"
        if let queryIndex = rawPath.firstIndex(of: "?") {
            rawPath = String(rawPath[..<queryIndex])
        }
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let name = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        // Only bare file names inside Documents: no subpaths, no "..".
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else {
            send(status: "404 Not Found", body: Data("Not found".utf8), contentType: "text/plain; charset=utf-8", on: connection)
            return
        }
        let fileURL = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL) else {
            send(status: "404 Not Found", body: Data("Not found".utf8), contentType: "text/plain; charset=utf-8", on: connection)
            return
        }
        send(status: "200 OK", body: data, contentType: mimeType(for: fileURL.pathExtension), on: connection)
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }

    private func send(status: String, body: Data, contentType: String, on connection: NWConnection) {
        var payload = Data("HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
