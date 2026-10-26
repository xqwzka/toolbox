import Foundation

/// Rule batch parsing, ported from the page's parseRuleBatch.
/// Accepts Clash, Quantumult X and Shadowrocket line formats.
/// Throws with the page's first-three-errors message.

let proxyRuleKinds = ["DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP", "PROCESS-NAME", "MATCH"]

func proxyNormalizeRuleKind(_ value: String) -> String {
    let key = value.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "_", with: "-")
    let aliases = [
        "HOST": "DOMAIN",
        "HOST-SUFFIX": "DOMAIN-SUFFIX",
        "HOST-KEYWORD": "DOMAIN-KEYWORD",
        "IP6-CIDR": "IP-CIDR6",
        "FINAL": "MATCH",
    ]
    return aliases[key] ?? key
}

/// Quote-aware comma split: commas inside quotes do not split,
/// and the quotes themselves are stripped.
func proxySplitRuleParts(_ value: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    for c in value {
        if (c == "\"" || c == "'") && quote == nil {
            quote = c
            continue
        }
        if let q = quote, c == q {
            quote = nil
            continue
        }
        if c == "," && quote == nil {
            parts.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
            continue
        }
        current.append(c)
    }
    parts.append(current.trimmingCharacters(in: .whitespaces))
    return parts
}

enum ProxyRuleBatchError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

func proxyParseRuleBatch(_ text: String, defaultPolicy: String, batchName: String) throws -> [ProxyRule] {
    let rows = text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
    var rules: [ProxyRule] = []
    var pendingName = ""
    var errors: [String] = []
    let ipv4Pattern = try? NSRegularExpression(pattern: #"^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$"#)
    let domainPattern = try? NSRegularExpression(pattern: #"^(?:\*\.)?[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+$"#)
    func matches(_ regex: NSRegularExpression?, _ s: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    for (index, raw) in rows.enumerated() {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("//") {
            // A preceding comment line names the next rule.
            let body = line.replacingOccurrences(of: #"^(?:#|;|//)\s*"#, with: "", options: .regularExpression)
            pendingName = body.trimmingCharacters(in: .whitespaces)
            continue
        }
        if line.range(of: #"^\[(?:Rule|Rules)\]$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
        if line.range(of: #"^(?:rules|payload)\s*:\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
        if line.hasPrefix("-") {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if (line.hasPrefix("'") && line.hasSuffix("'")) || (line.hasPrefix("\"") && line.hasSuffix("\"")) {
            line = String(line.dropFirst().dropLast())
        }
        line = proxyStripYamlComment(line).trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let parts = proxySplitRuleParts(line)
        var kind = proxyNormalizeRuleKind(parts[0])
        var value = ""
        var policy = ""
        var noResolve = false
        if proxyRuleKinds.contains(kind) {
            noResolve = parts.contains { $0.lowercased() == "no-resolve" }
            if kind == "MATCH" {
                if parts.count > 1 && parts[1].lowercased() != "no-resolve" {
                    policy = parts[1]
                } else {
                    policy = defaultPolicy
                }
            } else {
                value = parts.count > 1 ? parts[1] : ""
                if parts.count > 2 && parts[2].lowercased() != "no-resolve" {
                    policy = parts[2]
                } else {
                    policy = defaultPolicy
                }
            }
        } else if parts.count == 1 {
            value = parts[0]
            if matches(ipv4Pattern, value) {
                kind = "IP-CIDR"
            } else if value.contains(":") && value.contains("/") {
                kind = "IP-CIDR6"
            } else if matches(domainPattern, value) {
                kind = "DOMAIN-SUFFIX"
                if value.hasPrefix("*.") { value = String(value.dropFirst(2)) }
            } else {
                errors.append("第 \(index + 1) 行无法识别：\(line)")
                continue
            }
            policy = defaultPolicy
        } else {
            errors.append("第 \(index + 1) 行不支持规则类型 \(parts[0])")
            continue
        }
        if kind != "MATCH" && value.isEmpty {
            errors.append("第 \(index + 1) 行缺少匹配内容")
            continue
        }
        if policy.isEmpty { policy = defaultPolicy }
        rules.append(ProxyRule(
            id: newProxyID(),
            name: pendingName.isEmpty ? (batchName.isEmpty ? "导入规则 \(rules.count + 1)" : "\(batchName) \(rules.count + 1)") : pendingName,
            kind: kind, value: kind == "MATCH" ? "" : value, policy: policy, noResolve: noResolve
        ))
        pendingName = ""
    }
    if !errors.isEmpty {
        let shown = errors.prefix(3).joined(separator: "；")
        throw ProxyRuleBatchError.message(shown + (errors.count > 3 ? "；另有 \(errors.count - 3) 行未识别" : ""))
    }
    if rules.isEmpty {
        throw ProxyRuleBatchError.message("没有识别到可加入的规则。")
    }
    return rules
}
