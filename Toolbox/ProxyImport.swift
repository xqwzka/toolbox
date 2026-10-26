import Foundation

/// YAML subset parser + Clash import, ported from the page's
/// parseYamlSubset / importedState. Only the subset the page
/// understands is supported: block maps/sequences, quoted and
/// plain scalars, comments. Tabs are rejected like the page.

// MARK: - YAML value

indirect enum YamlNode {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([YamlNode])
    case object([String: YamlNode])

    var asObject: [String: YamlNode]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var asArray: [YamlNode]? {
        if case .array(let a) = self { return a }
        return nil
    }

    func asString(default defaultValue: String = "") -> String {
        switch self {
        case .string(let s): return s
        case .int(let n): return "\(n)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        default: return defaultValue
        }
    }

    func asInt(default defaultValue: Int = 0) -> Int {
        switch self {
        case .int(let n): return n
        case .double(let d): return Int(d)
        case .string(let s): return Int(s) ?? defaultValue
        default: return defaultValue
        }
    }
}

struct YamlLine {
    var indent: Int
    var content: String
    var line: Int
}

enum ProxyImportError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

func proxyStripYamlComment(_ value: String) -> String {
    var single = false
    var double = false
    let chars = Array(value)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "'" && !double {
            if single && i + 1 < chars.count && chars[i + 1] == "'" {
                i += 2
                continue
            }
            single.toggle()
        } else if c == "\"" && !single {
            if !(i > 0 && chars[i - 1] == "\\") { double.toggle() }
        } else if c == "#" && !single && !double && (i == 0 || chars[i - 1].isWhitespace) {
            return String(chars[..<i]).trimmingCharacters(in: .whitespaces)
        }
        i += 1
    }
    return value.trimmingCharacters(in: .whitespaces)
}

func proxyYamlKeyValue(_ value: String) -> (key: String, value: String)? {
    var single = false
    var double = false
    let chars = Array(value)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "'" && !double {
            if single && i + 1 < chars.count && chars[i + 1] == "'" {
                i += 2
                continue
            }
            single.toggle()
        } else if c == "\"" && !single {
            if !(i > 0 && chars[i - 1] == "\\") { double.toggle() }
        } else if c == ":" && !single && !double {
            let key = String(chars[..<i]).trimmingCharacters(in: .whitespaces)
            let val = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
            return (key, val)
        }
        i += 1
    }
    return nil
}

func proxyYamlScalar(_ value: String) -> YamlNode {
    let v = proxyStripYamlComment(value).trimmingCharacters(in: .whitespaces)
    if v == "''" || v == "\"\"" { return .string("") }
    if v.hasPrefix("'") && v.hasSuffix("'") && v.count >= 2 {
        return .string(String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
    }
    if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
        let inner = String(v.dropFirst().dropLast())
        if let data = "\"\(inner)\"".data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String {
            return .string(decoded)
        }
        return .string(inner)
    }
    if v == "[]" { return .array([]) }
    if v == "{}" { return .object([:]) }
    if v == "true" { return .bool(true) }
    if v == "false" { return .bool(false) }
    if v == "null" || v == "~" { return .null }
    if v.range(of: #"^-?(?:\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil {
        if v.contains(".") {
            if let d = Double(v) { return .double(d) }
        } else if let n = Int(v) {
            return .int(n)
        }
    }
    return .string(v)
}

func proxyParseYamlBlock(_ lines: [YamlLine], _ start: Int, _ indent: Int) throws -> (YamlNode, Int) {
    guard start < lines.count else { return (.null, start) }
    let isSequence = lines[start].indent == indent && lines[start].content.hasPrefix("- ")
    if isSequence {
        var list: [YamlNode] = []
        var i = start
        while i < lines.count && lines[i].indent == indent && lines[i].content.hasPrefix("- ") {
            let remainder = String(lines[i].content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            var j = i + 1
            while j < lines.count && lines[j].indent > indent { j += 1 }
            if let pair = proxyYamlKeyValue(remainder) {
                _ = pair
                let virtual = [YamlLine(indent: indent + 2, content: remainder, line: lines[i].line)] + Array(lines[(i + 1)..<j])
                let parsed = try proxyParseYamlBlock(virtual, 0, indent + 2)
                list.append(parsed.0)
            } else if !remainder.isEmpty {
                list.append(proxyYamlScalar(remainder))
            } else if i + 1 < j {
                let parsed = try proxyParseYamlBlock(lines, i + 1, lines[i + 1].indent)
                list.append(parsed.0)
            } else {
                list.append(.null)
            }
            i = j
        }
        return (.array(list), i)
    }
    var object: [String: YamlNode] = [:]
    var k = start
    while k < lines.count && lines[k].indent == indent && !lines[k].content.hasPrefix("- ") {
        guard let kv = proxyYamlKeyValue(lines[k].content) else {
            throw ProxyImportError.message("第 \(lines[k].line) 行无法识别")
        }
        if kv.key.isEmpty {
            throw ProxyImportError.message("第 \(lines[k].line) 行缺少字段名")
        }
        let key = proxyYamlScalar(kv.key).asString()
        if !kv.value.isEmpty {
            object[key] = proxyYamlScalar(kv.value)
            k += 1
        } else if k + 1 < lines.count && lines[k + 1].indent > indent {
            let child = try proxyParseYamlBlock(lines, k + 1, lines[k + 1].indent)
            object[key] = child.0
            k = child.1
        } else {
            object[key] = .null
            k += 1
        }
    }
    return (.object(object), k)
}

func proxyParseYamlSubset(_ text: String) throws -> [String: YamlNode] {
    let source = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    let rows = source.components(separatedBy: .newlines)
    var lines: [YamlLine] = []
    for (index, row) in rows.enumerated() {
        if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        if row.range(of: #"^\s*#"#, options: .regularExpression) != nil { continue }
        if row.range(of: #"^\s*(---|\.\.\.)\s*$"#, options: .regularExpression) != nil { continue }
        if row.range(of: #"^\s*\t"#, options: .regularExpression) != nil {
            throw ProxyImportError.message("第 \(index + 1) 行使用了 Tab 缩进，请改用空格")
        }
        let leading = row.prefix(while: { $0 == " " }).count
        let rest = String(row.dropFirst(leading))
        lines.append(YamlLine(indent: leading, content: proxyStripYamlComment(rest).trimmingCharacters(in: .whitespaces), line: index + 1))
    }
    if lines.isEmpty {
        throw ProxyImportError.message("文件里没有可读取的 YAML 内容")
    }
    if lines[0].indent != 0 {
        throw ProxyImportError.message("YAML 顶层不能缩进")
    }
    let parsed = try proxyParseYamlBlock(lines, 0, 0)
    guard let object = parsed.0.asObject else {
        throw ProxyImportError.message("需要导入 Clash 配置对象")
    }
    return object
}

// MARK: - Comment-annotated section extraction

struct ProxyRuleEntry {
    var name: String
    var value: String
}

func proxyExtractRuleEntries(_ text: String) -> [ProxyRuleEntry] {
    let rows = text.components(separatedBy: .newlines)
    var inside = false
    var pending = ""
    var entries: [ProxyRuleEntry] = []
    for row in rows {
        if !inside {
            if row.range(of: #"^rules:\s*(?:#.*)?$"#, options: .regularExpression) != nil {
                inside = true
            }
            continue
        }
        if row.range(of: #"^\S"#, options: .regularExpression) != nil && !row.trimmingCharacters(in: .whitespaces).isEmpty {
            break
        }
        if let match = row.range(of: #"^\s+#\s*(.+?)\s*$"#, options: .regularExpression) {
            // Recover the comment body after the '#'.
            let hashIndex = row.firstIndex(of: "#")!
            pending = String(row[row.index(after: hashIndex)...]).trimmingCharacters(in: .whitespaces)
            _ = match
            continue
        }
        if let match = row.range(of: #"^\s+-\s*(.+?)\s*$"#, options: .regularExpression) {
            let dashRange = row.range(of: "-")!
            let item = String(row[row.index(after: dashRange)...]).trimmingCharacters(in: .whitespaces)
            _ = match
            entries.append(ProxyRuleEntry(name: pending, value: proxyYamlScalar(item).asString()))
            pending = ""
        }
    }
    return entries
}

func proxyExtractSectionNames(_ text: String, section: String, label: String) -> [String: String] {
    let rows = text.components(separatedBy: .newlines)
    var inside = false
    var pending = ""
    var names: [String: String] = [:]
    for row in rows {
        if !inside {
            if row.trimmingCharacters(in: .whitespaces) == section + ":" { inside = true }
            continue
        }
        if row.range(of: #"^\S"#, options: .regularExpression) != nil && !row.trimmingCharacters(in: .whitespaces).isEmpty {
            break
        }
        if row.range(of: #"^\s{2}#\s*(.+?)\s*$"#, options: .regularExpression) != nil {
            let hashIndex = row.firstIndex(of: "#")!
            let comment = String(row[row.index(after: hashIndex)...]).trimmingCharacters(in: .whitespaces)
            let labelPattern = "^" + NSRegularExpression.escapedPattern(for: label) + "\\s*[:：]\\s*(.+)$"
            if let labelMatch = comment.range(of: labelPattern, options: .regularExpression) {
                pending = String(comment[labelMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                pending = ""
            }
            continue
        }
        if let keyRange = row.range(of: #"^\s{2}([^#][^:]*):\s*$"#, options: .regularExpression) {
            let keyText = String(row[keyRange]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ":$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let key = proxyYamlScalar(keyText).asString()
            if !pending.isEmpty { names[key] = pending }
            pending = ""
        }
    }
    return names
}

func proxyExtractAutoGroups(_ text: String, marker: String) -> Set<String> {
    let rows = text.components(separatedBy: .newlines)
    var inside = false
    var current = ""
    var marked = Set<String>()
    for row in rows {
        if !inside {
            if row.trimmingCharacters(in: .whitespaces) == "proxy-groups:" { inside = true }
            continue
        }
        if row.range(of: #"^\S"#, options: .regularExpression) != nil && !row.trimmingCharacters(in: .whitespaces).isEmpty {
            break
        }
        if let nameRange = row.range(of: #"^\s{2}-\s+name:\s*(.+?)\s*$"#, options: .regularExpression) {
            let nameText = String(row[nameRange]).replacingOccurrences(of: #"^\s{2}-\s+name:\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            current = proxyYamlScalar(nameText).asString()
            continue
        }
        if !current.isEmpty && row.range(of: marker, options: .regularExpression) != nil {
            marked.insert(current)
        }
    }
    return marked
}

// MARK: - nodeToLink (Clash proxy entry -> share link)

private func proxyB64Encode(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
}

private func proxyPercentEncodeUserInfo(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
}

private func proxyURLHost(_ value: String) -> String {
    value.contains(":") ? "[\(value)]" : value
}

/// Returns (name, url) or an error message, mirroring the page.
func proxyNodeToLink(_ node: [String: YamlNode]) -> Result<(name: String, url: String), String> {
    let type = node["type"]?.asString().lowercased() ?? ""
    let server = node["server"]?.asString() ?? ""
    let port = node["port"]?.asInt() ?? 0
    let name = node["name"]?.asString() ?? ""
    let displayName = name.isEmpty ? type.uppercased() + " 节点" : name
    let host = proxyURLHost(server)
    if host.isEmpty || port == 0 {
        return .failure("节点「\(displayName)」缺少服务器或端口")
    }
    func finish(_ url: String) -> Result<(name: String, url: String), String> {
        .success((displayName, url))
    }
    switch type {
    case "ss":
        if node["plugin"] != nil {
            return .failure("节点「\(displayName)」使用了暂不支持导回编辑器的 SS 插件")
        }
        let cipher = node["cipher"]?.asString() ?? ""
        let password = node["password"]?.asString() ?? ""
        return finish("ss://" + proxyB64Encode("\(cipher):\(password)") + "@\(host):\(port)#" + proxyPercentEncodeUserInfo(displayName))
    case "vmess":
        let ws = node["ws-opts"]?.asObject ?? [:]
        let headers = ws["headers"]?.asObject ?? [:]
        let uuid = node["uuid"]?.asString() ?? ""
        if uuid.isEmpty {
            return .failure("节点「\(displayName)」缺少 UUID")
        }
        let alterId: Int
        if let v = node["alterId"] { alterId = v.asInt() }
        else if let v = node["alter-id"] { alterId = v.asInt() }
        else { alterId = 0 }
        var mutable: [String: Any] = [
            "v": "2", "ps": displayName, "add": server, "port": "\(port)", "id": uuid,
            "aid": "\(alterId)", "scy": node["cipher"]?.asString() ?? "auto",
            "net": node["network"]?.asString() ?? "tcp", "type": "none",
            "host": headers["Host"]?.asString() ?? headers["host"]?.asString() ?? "",
            "path": ws["path"]?.asString() ?? "",
            "sni": node["servername"]?.asString() ?? node["sni"]?.asString() ?? "",
        ]
        var tlsOn = false
        if let tlsNode = node["tls"], case .bool(let b) = tlsNode { tlsOn = b }
        mutable["tls"] = tlsOn ? "tls" : ""
        let jsonData = (try? JSONSerialization.data(withJSONObject: mutable)) ?? Data()
        return finish("vmess://" + jsonData.base64EncodedString())
    case "trojan":
        var components = URLComponents()
        components.scheme = "trojan"
        components.user = node["password"]?.asString() ?? ""
        components.host = server
        components.port = port
        var items: [URLQueryItem] = []
        let sni = node["sni"]?.asString() ?? node["servername"]?.asString() ?? ""
        if !sni.isEmpty { items.append(URLQueryItem(name: "sni", value: sni)) }
        if let skipNode = node["skip-cert-verify"], case .bool(let skip) = skipNode, skip {
            items.append(URLQueryItem(name: "allowInsecure", value: "1"))
        }
        if !items.isEmpty { components.queryItems = items }
        components.fragment = displayName
        guard let url = components.url?.absoluteString else {
            return .failure("节点「\(displayName)」无法生成链接")
        }
        return finish(url)
    case "vless":
        let reality = node["reality-opts"]?.asObject ?? [:]
        let uuid = node["uuid"]?.asString() ?? ""
        if uuid.isEmpty {
            return .failure("节点「\(displayName)」缺少 UUID")
        }
        var components = URLComponents()
        components.scheme = "vless"
        components.user = uuid
        components.host = server
        components.port = port
        var items: [URLQueryItem] = []
        items.append(URLQueryItem(name: "encryption", value: node["encryption"]?.asString() ?? "none"))
        var tlsOn = false
        if let tlsNode = node["tls"], case .bool(let b) = tlsNode { tlsOn = b }
        items.append(URLQueryItem(name: "security", value: reality.isEmpty ? (tlsOn ? "tls" : "none") : "reality"))
        items.append(URLQueryItem(name: "type", value: node["network"]?.asString() ?? "tcp"))
        let sni = node["servername"]?.asString() ?? node["sni"]?.asString() ?? ""
        if !sni.isEmpty { items.append(URLQueryItem(name: "sni", value: sni)) }
        if let flow = node["flow"]?.asString(), !flow.isEmpty { items.append(URLQueryItem(name: "flow", value: flow)) }
        if let fp = node["client-fingerprint"]?.asString(), !fp.isEmpty { items.append(URLQueryItem(name: "fp", value: fp)) }
        if let pbk = reality["public-key"]?.asString(), !pbk.isEmpty { items.append(URLQueryItem(name: "pbk", value: pbk)) }
        if let sid = reality["short-id"]?.asString(), !sid.isEmpty { items.append(URLQueryItem(name: "sid", value: sid)) }
        if let spx = reality["spider-x"]?.asString(), !spx.isEmpty { items.append(URLQueryItem(name: "spx", value: spx)) }
        if let skipNode = node["skip-cert-verify"], case .bool(let skip) = skipNode, skip {
            items.append(URLQueryItem(name: "allowInsecure", value: "1"))
        }
        let ws = node["ws-opts"]?.asObject ?? [:]
        if let path = ws["path"]?.asString(), !path.isEmpty { items.append(URLQueryItem(name: "path", value: path)) }
        let wsHeaders = ws["headers"]?.asObject ?? [:]
        if let wsHost = wsHeaders["Host"]?.asString() ?? wsHeaders["host"]?.asString(), !wsHost.isEmpty {
            items.append(URLQueryItem(name: "host", value: wsHost))
        }
        components.queryItems = items
        components.fragment = displayName
        guard let url = components.url?.absoluteString else {
            return .failure("节点「\(displayName)」无法生成链接")
        }
        return finish(url)
    case "hysteria2", "hy2":
        var components = URLComponents()
        components.scheme = "hysteria2"
        components.user = node["password"]?.asString() ?? node["auth"]?.asString() ?? ""
        components.host = server
        components.port = port
        var items: [URLQueryItem] = []
        if let sni = node["sni"]?.asString(), !sni.isEmpty { items.append(URLQueryItem(name: "sni", value: sni)) }
        if let skipNode = node["skip-cert-verify"], case .bool(let skip) = skipNode, skip {
            items.append(URLQueryItem(name: "allowInsecure", value: "1"))
        }
        if !items.isEmpty { components.queryItems = items }
        components.fragment = displayName
        guard let url = components.url?.absoluteString else {
            return .failure("节点「\(displayName)」无法生成链接")
        }
        return finish(url)
    default:
        return .failure("节点「\(displayName)」的类型 \(type) 暂不支持导回编辑器")
    }
}

// MARK: - importedState

struct ProxyImportedConfig {
    var config: ConfigData
    var warnings: [String]
}

func proxyImportedState(_ text: String) throws -> ProxyImportedConfig {
    let doc = try proxyParseYamlSubset(text)
    var result = ConfigData(
        subscriptions: [], nodeLinks: [], strategies: [], providers: [], rules: [],
        fallback: ProxyFallback(cn: "DIRECT", defaultPolicy: "Proxy")
    )
    var warnings: [String] = []
    let ruleEntries = proxyExtractRuleEntries(text)
    let subscriptionNames = proxyExtractSectionNames(text, section: "proxy-providers", label: "订阅名称")
    let autoSubscriptionGroups = proxyExtractAutoGroups(text, marker: #"^\s{4}#\s*订阅来源:\s*自动全选"#)
    let autoNodeGroups = proxyExtractAutoGroups(text, marker: #"^\s{4}#\s*单个节点来源:\s*(?:按地区自动匹配|自动全选)"#)
    var providerRules: [String: (name: String, policy: String)] = [:]
    for entry in ruleEntries {
        let parts = entry.value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts[0] == "RULE-SET", parts.count > 1 {
            providerRules[parts[1]] = (entry.name, parts.count > 2 ? parts[2] : "DIRECT")
        }
    }
    if let providers = doc["proxy-providers"]?.asObject {
        for key in providers.keys {
            let item = providers[key]?.asObject ?? [:]
            if let type = item["type"]?.asString(), type != "http" {
                warnings.append("节点订阅「\(key)」不是 http 类型，已按普通订阅导入")
            }
            result.subscriptions.append(ProxySubscription(
                id: newProxyID(), key: key, name: subscriptionNames[key] ?? key,
                url: item["url"]?.asString() ?? "", interval: item["interval"]?.asInt(default: 86400) ?? 86400
            ))
        }
    }
    if let proxies = doc["proxies"]?.asArray {
        for node in proxies {
            guard let object = node.asObject else { continue }
            switch proxyNodeToLink(object) {
            case .success(let converted):
                result.nodeLinks.append(ProxyNodeLink(id: newProxyID(), name: converted.name, url: converted.url))
            case .failure(let message):
                warnings.append(message)
            }
        }
    }
    if let groups = doc["proxy-groups"]?.asArray {
        for groupNode in groups {
            guard let group = groupNode.asObject else { continue }
            let groupName = group["name"]?.asString() ?? ""
            if groupName.isEmpty || groupName == "Proxy" { continue }
            let importedUses = (group["use"]?.asArray ?? []).map { $0.asString() }
            let sourceSubscriptions = result.subscriptions.filter {
                importedUses.contains(proxySubscriptionKey($0)) || importedUses.contains($0.name)
            }.map { $0.id }
            let importedFilter = group["filter"]?.asString() ?? ""
            let importedRegions = proxyInferRegions(importedFilter)
            var importedMembers = proxyUniqueValues((group["proxies"]?.asArray ?? []).map { $0.asString() })
            let importedProxy = importedMembers.contains("Proxy")
            let nodeSources = result.nodeLinks.filter { importedMembers.contains($0.name) }.map { $0.id }
            let exactNodeNames = result.nodeLinks.filter { nodeSources.contains($0.id) }.map { $0.name }
            importedMembers.removeAll { $0 == "Proxy" || exactNodeNames.contains($0) }
            result.strategies.append(ProxyStrategy(
                id: newProxyID(), name: groupName, type: group["type"]?.asString() ?? "select",
                members: importedMembers.joined(separator: "\n"), uses: "",
                sourceSubscriptions: sourceSubscriptions, nodeSources: nodeSources,
                regions: importedRegions, customFilter: importedRegions.isEmpty ? importedFilter : "",
                dialerProxy: group["dialer-proxy"]?.asString() ?? "", includeProxy: importedProxy,
                autoAllSubscriptions: autoSubscriptionGroups.contains(groupName),
                autoAllNodes: autoNodeGroups.contains(groupName)
            ))
        }
    }
    if let ruleProviders = doc["rule-providers"]?.asObject {
        for key in ruleProviders.keys {
            let item = ruleProviders[key]?.asObject ?? [:]
            let ref = providerRules[key]
            result.providers.append(ProxyProvider(
                id: newProxyID(), key: key, name: ref?.name ?? key,
                url: item["url"]?.asString() ?? "",
                behavior: item["behavior"]?.asString() ?? "classical",
                policy: ref?.policy ?? "DIRECT"
            ))
        }
    }
    struct ParsedRule {
        var name: String
        var kind: String
        var value: String
        var policy: String
        var noResolve: Bool
    }
    var parsedRules: [ParsedRule] = []
    for (index, entry) in ruleEntries.enumerated() {
        var parts = entry.value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var noResolve = false
        if parts.last == "no-resolve" {
            noResolve = true
            parts.removeLast()
        }
        let kind = parts[0]
        let name = entry.name.isEmpty ? "导入规则 \(index + 1)" : entry.name
        let value = kind == "MATCH" ? "" : (parts.count > 1 ? parts[1] : "")
        let policy = kind == "MATCH"
            ? (parts.count > 1 ? parts[1] : "DIRECT")
            : (parts.count > 2 ? parts[2] : "DIRECT")
        parsedRules.append(ParsedRule(name: name, kind: kind, value: value, policy: policy, noResolve: noResolve))
    }
    func containsCNOrDomestic(_ s: String) -> Bool {
        s.contains("CN") || s.contains("国内")
    }
    func containsDefault(_ s: String) -> Bool {
        s.contains("默认") || s.contains("兜底")
    }
    var cnIndex = parsedRules.firstIndex { $0.kind == "GEOIP" && $0.value == "CN" && containsCNOrDomestic($0.name) } ?? -1
    if cnIndex < 0 {
        cnIndex = parsedRules.lastIndex { $0.kind == "GEOIP" && $0.value == "CN" } ?? -1
    }
    var defaultIndex = parsedRules.firstIndex { $0.kind == "MATCH" && containsDefault($0.name) } ?? -1
    if defaultIndex < 0 {
        defaultIndex = parsedRules.lastIndex { $0.kind == "MATCH" } ?? -1
    }
    if cnIndex >= 0 { result.fallback.cn = parsedRules[cnIndex].policy }
    if defaultIndex >= 0 { result.fallback.defaultPolicy = parsedRules[defaultIndex].policy }
    for (index, rule) in parsedRules.enumerated() {
        if rule.kind == "RULE-SET" || index == cnIndex || index == defaultIndex { continue }
        result.rules.append(ProxyRule(
            id: newProxyID(), name: rule.name, kind: rule.kind, value: rule.value,
            policy: rule.policy, noResolve: rule.noResolve
        ))
    }
    let recognized = ["proxy-providers", "proxies", "proxy-groups", "rule-providers", "rules"].contains { doc[$0] != nil }
    if !recognized {
        throw ProxyImportError.message("没有找到节点、策略组、规则订阅或分流规则")
    }
    return ProxyImportedConfig(config: result, warnings: warnings)
}
