import Foundation

/// Parsed share link, ported from the page's parseNodeLink.
/// `error` is non-nil exactly when `ok` is false, with the
/// page's Chinese messages.
struct ParsedProxyNode: Equatable {
    var ok: Bool
    var error: String?
    var protocolName: String
    var name: String
    var server: String
    var port: Int
    var uuid: String = ""
    var alterId: Int = 0
    var cipher: String = ""
    var password: String = ""
    var network: String = ""
    var tls: Bool = false
    var sni: String = ""
    var path: String = ""
    var host: String = ""
    var skipCertVerify: Bool = false
    var encryption: String = ""
    var flow: String = ""
    var clientFingerprint: String = ""
    var reality: Bool = false
    var publicKey: String = ""
    var shortId: String = ""
    var spiderX: String = ""

    static func failure(_ message: String, name: String) -> ParsedProxyNode {
        ParsedProxyNode(ok: false, error: message, protocolName: "", name: name, server: "", port: 0)
    }
}

private func proxyB64Decode(_ value: String) -> String {
    var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    guard let data = Data(base64Encoded: s) else { return "" }
    // The page percent-decodes the UTF-8 bytes; on failure it
    // keeps the raw binary string. UTF-8 covers every real link.
    return String(data: data, encoding: .utf8) ?? ""
}

private func proxySafeDecode(_ value: String) -> String {
    value.removingPercentEncoding ?? value
}

private func proxyQueryItems(_ url: URL) -> [String: String] {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems else { return [:] }
    var out: [String: String] = [:]
    for item in items { out[item.name] = item.value ?? "" }
    return out
}

/// Port of the page's parseNodeLink, including its rejections:
/// SS links with plugin params, VMess non-tcp/ws transports and
/// TCP disguise, VLESS non-tcp/ws transports and non-none
/// encryption, Trojan non-tcp transports, and unknown params.
func parseProxyNodeLink(_ raw: String, fallbackName: String) -> ParsedProxyNode {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let hashIndex = text.firstIndex(of: "#")
    let note = hashIndex.map { proxySafeDecode(String(text[text.index(after: $0)...])) } ?? ""
    let clean = hashIndex.map { String(text[..<$0]) } ?? text
    let displayName = fallbackName.isEmpty ? nil : fallbackName

    func fail(_ message: String) -> ParsedProxyNode {
        ParsedProxyNode.failure(message, name: displayName ?? note)
    }

    if clean.hasPrefix("vmess://") {
        let decoded = proxyB64Decode(String(clean.dropFirst("vmess://".count)))
        guard let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let add = json["add"] as? String, !add.isEmpty,
              let portValue = json["port"],
              let id = json["id"] as? String, !id.isEmpty else {
            return fail("链接解析失败：字段不完整")
        }
        let port: Int
        if let n = portValue as? Int { port = n }
        else if let s = portValue as? String, let n = Int(s) { port = n }
        else { return fail("链接解析失败：字段不完整") }
        let net = json["net"] as? String ?? ""
        if !net.isEmpty && net != "tcp" && net != "ws" {
            return fail("链接解析失败：暂不支持此 VMess 传输类型")
        }
        if (net.isEmpty || net == "tcp"), let type = json["type"] as? String, type != "none" {
            return fail("链接解析失败：暂不支持带 TCP 伪装的 VMess 链接")
        }
        let tls = (json["tls"] as? String) == "tls"
        var node = ParsedProxyNode(ok: true, error: nil, protocolName: "vmess",
                                   name: displayName ?? (json["ps"] as? String) ?? note,
                                   server: add, port: port)
        if node.name.isEmpty { node.name = "VMess 节点" }
        node.uuid = id
        if let aid = json["aid"] as? Int { node.alterId = aid }
        else if let aid = json["aid"] as? String, let n = Int(aid) { node.alterId = n }
        node.cipher = (json["scy"] as? String) ?? "auto"
        node.network = net
        node.tls = tls
        node.sni = (json["sni"] as? String) ?? (json["host"] as? String) ?? ""
        node.path = (json["path"] as? String) ?? ""
        node.host = (json["host"] as? String) ?? ""
        return node
    }

    if clean.hasPrefix("ss://") {
        if clean.contains("?") {
            return fail("链接解析失败：暂不转换带插件参数的 SS 链接")
        }
        let body = String(clean.dropFirst("ss://".count)).components(separatedBy: "?")[0]
        let decoded: String
        if !body.contains("@") {
            decoded = proxyB64Decode(body)
        } else {
            let atIndex = body.firstIndex(of: "@")!
            let left = String(body[..<atIndex])
            let right = String(body[body.index(after: atIndex)...])
            decoded = (left.contains(":") ? proxySafeDecode(left) : proxyB64Decode(left)) + "@" + right
        }
        guard let regex = try? NSRegularExpression(pattern: #"^([^:]+):(.+)@(\[[^\]]+\]|[^:]+):(\d+)$"#),
              let match = regex.firstMatch(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)),
              let cipherRange = Range(match.range(at: 1), in: decoded),
              let passwordRange = Range(match.range(at: 2), in: decoded),
              let serverRange = Range(match.range(at: 3), in: decoded),
              let portRange = Range(match.range(at: 4), in: decoded),
              let port = Int(decoded[portRange]) else {
            return fail("链接解析失败：格式无法识别")
        }
        var node = ParsedProxyNode(ok: true, error: nil, protocolName: "ss",
                                   name: displayName ?? note,
                                   server: String(decoded[serverRange]).trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
                                   port: port)
        if node.name.isEmpty { node.name = "SS 节点" }
        node.cipher = String(decoded[cipherRange])
        node.password = proxySafeDecode(String(decoded[passwordRange]))
        return node
    }

    let lowerClean = clean.lowercased()
    if lowerClean.hasPrefix("trojan://") || lowerClean.hasPrefix("vless://") ||
        lowerClean.hasPrefix("hysteria2://") || lowerClean.hasPrefix("hy2://") {
        guard let url = URL(string: clean),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return fail("链接解析失败：格式无法识别")
        }
        var proto = (components.scheme ?? "").lowercased()
        if proto == "hy2" { proto = "hysteria2" }
        let allowed: [String]
        switch proto {
        case "vless":
            allowed = ["type", "security", "sni", "peer", "allowInsecure", "insecure", "flow", "path", "host", "encryption", "fp", "pbk", "sid", "spx"]
        case "trojan":
            allowed = ["sni", "peer", "allowInsecure", "insecure", "type"]
        default:
            allowed = ["sni", "peer", "allowInsecure", "insecure"]
        }
        let params = proxyQueryItems(url)
        let unsupported = params.keys.filter { !allowed.contains($0) }.sorted()
        if !unsupported.isEmpty {
            return fail("链接解析失败：暂不转换参数：" + unsupported.joined(separator: ", "))
        }
        if proto == "vless" {
            if let type = params["type"], !type.isEmpty && type != "tcp" && type != "ws" {
                return fail("链接解析失败：暂不支持此 VLESS 传输类型")
            }
            if let encryption = params["encryption"], !encryption.isEmpty && encryption != "none" {
                return fail("链接解析失败：仅支持 encryption=none 的 VLESS 链接")
            }
        }
        if proto == "trojan" {
            if let type = params["type"], !type.isEmpty && type != "tcp" {
                return fail("链接解析失败：暂不支持此 Trojan 传输类型")
            }
        }
        let host = components.host ?? ""
        let port = components.port ?? 443
        if host.isEmpty || port == 0 {
            return fail("链接解析失败：服务器字段不完整")
        }
        var node = ParsedProxyNode(ok: true, error: nil, protocolName: proto,
                                   name: displayName ?? note,
                                   server: host, port: port)
        if node.name.isEmpty { node.name = proto.uppercased() + " 节点" }
        node.sni = params["sni"] ?? params["peer"] ?? ""
        node.skipCertVerify = params["allowInsecure"] == "1" || params["insecure"] == "1"
        if proto == "trojan" {
            node.password = proxySafeDecode(components.user ?? "")
        } else if proto == "vless" {
            let security = (params["security"] ?? "").lowercased()
            node.uuid = proxySafeDecode(components.user ?? "")
            node.network = params["type"] ?? "tcp"
            node.tls = security == "tls" || security == "reality"
            node.reality = security == "reality"
            node.encryption = params["encryption"] ?? ""
            node.flow = params["flow"] ?? ""
            node.path = params["path"] ?? ""
            node.host = params["host"] ?? ""
            node.clientFingerprint = params["fp"] ?? ""
            node.publicKey = params["pbk"] ?? ""
            node.shortId = params["sid"] ?? ""
            node.spiderX = params["spx"] ?? ""
        } else if proto == "hysteria2" {
            let user = components.user ?? ""
            node.password = proxySafeDecode(user.isEmpty ? (components.password ?? "") : user)
        }
        return node
    }

    return ParsedProxyNode.failure("暂不识别这个协议；支持 ss、vmess、trojan、vless、hysteria2。",
                                   name: displayName ?? note)
}

/// Port of the page's nodeYaml: one Clash proxy entry.
func proxyNodeYaml(_ node: ParsedProxyNode) -> [String] {
    var out = [
        "  - name: " + proxyYamlQuote(node.name),
        "    type: " + node.protocolName,
        "    server: " + proxyYamlQuote(node.server),
        "    port: \(node.port)",
    ]
    switch node.protocolName {
    case "ss":
        out.append("    cipher: " + proxyYamlQuote(node.cipher))
        out.append("    password: " + proxyYamlQuote(node.password))
    case "vmess":
        out.append("    uuid: " + proxyYamlQuote(node.uuid))
        out.append("    alterId: \(node.alterId)")
        out.append("    cipher: " + proxyYamlQuote(node.cipher))
        if node.tls { out.append("    tls: true") }
        if !node.sni.isEmpty { out.append("    servername: " + proxyYamlQuote(node.sni)) }
        if !node.network.isEmpty && node.network != "tcp" {
            out.append("    network: " + node.network)
            if node.network == "ws" {
                out.append("    ws-opts:")
                if !node.path.isEmpty { out.append("      path: " + proxyYamlQuote(node.path)) }
                if !node.host.isEmpty {
                    out.append("      headers:")
                    out.append("        Host: " + proxyYamlQuote(node.host))
                }
            }
        }
    case "trojan":
        out.append("    password: " + proxyYamlQuote(node.password))
        if !node.sni.isEmpty { out.append("    sni: " + proxyYamlQuote(node.sni)) }
        if node.skipCertVerify { out.append("    skip-cert-verify: true") }
    case "vless":
        out.append("    uuid: " + proxyYamlQuote(node.uuid))
        out.append("    network: " + node.network)
        if !node.encryption.isEmpty { out.append("    encryption: " + proxyYamlQuote(node.encryption)) }
        if node.tls { out.append("    tls: true") }
        if !node.sni.isEmpty { out.append("    servername: " + proxyYamlQuote(node.sni)) }
        if node.skipCertVerify { out.append("    skip-cert-verify: true") }
        if !node.flow.isEmpty { out.append("    flow: " + proxyYamlQuote(node.flow)) }
        if !node.clientFingerprint.isEmpty { out.append("    client-fingerprint: " + proxyYamlQuote(node.clientFingerprint)) }
        if node.reality {
            out.append("    reality-opts:")
            if !node.publicKey.isEmpty { out.append("      public-key: " + proxyYamlQuote(node.publicKey)) }
            if !node.shortId.isEmpty { out.append("      short-id: " + proxyYamlQuote(node.shortId)) }
            if !node.spiderX.isEmpty { out.append("      spider-x: " + proxyYamlQuote(node.spiderX)) }
        }
        if node.network == "ws" {
            out.append("    ws-opts:")
            if !node.path.isEmpty { out.append("      path: " + proxyYamlQuote(node.path)) }
            if !node.host.isEmpty {
                out.append("      headers:")
                out.append("        Host: " + proxyYamlQuote(node.host))
            }
        }
    case "hysteria2":
        out.append("    password: " + proxyYamlQuote(node.password))
        if !node.sni.isEmpty { out.append("    sni: " + proxyYamlQuote(node.sni)) }
        if node.skipCertVerify { out.append("    skip-cert-verify: true") }
    default:
        break
    }
    return out
}
