import Foundation

// MARK: - Region helpers (ported from the page)

func proxyRegionKeys(_ value: [String]) -> [String] {
    proxyUniqueValues(value).filter { key in
        proxyRegionCatalog.contains { $0.key == key }
    }
}

func proxyRegionDefs(_ keys: [String]) -> [RegionDef] {
    let wanted = proxyRegionKeys(keys)
    return proxyRegionCatalog.filter { wanted.contains($0.key) }
}

/// Clash filter string: (?i)(pattern1|pattern2) or "".
func proxyRegionFilter(_ keys: [String]) -> String {
    let patterns = proxyRegionDefs(keys).map { $0.pattern }
    return patterns.isEmpty ? "" : "(?i)(" + patterns.joined(separator: "|") + ")"
}

/// Inverse of proxyRegionFilter: find the region set whose
/// filter string matches exactly (brute force over subsets,
/// as the page does).
func proxyInferRegions(_ filter: String) -> [String] {
    if filter.isEmpty { return [] }
    let count = proxyRegionCatalog.count
    for mask in 1..<(1 << count) {
        var keys: [String] = []
        for j in 0..<count where mask & (1 << j) != 0 {
            keys.append(proxyRegionCatalog[j].key)
        }
        if proxyRegionFilter(keys) == filter { return keys }
    }
    return []
}

private var proxyRegexCache: [String: NSRegularExpression?] = [:]

private func proxyRegionRegex(_ pattern: String) -> NSRegularExpression? {
    if let cached = proxyRegexCache[pattern] { return cached }
    let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    proxyRegexCache[pattern] = compiled
    return compiled
}

func proxyMatchesRegions(_ name: String, keys: [String]) -> Bool {
    proxyRegionDefs(keys).contains { region in
        guard let regex = proxyRegionRegex(region.pattern) else { return false }
        return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

func proxyRegionLabels(_ keys: [String]) -> [String] {
    proxyRegionDefs(keys).map { $0.label }
}

func proxyRegexEscape(_ value: String) -> String {
    var out = ""
    for c in value {
        if ".*+?^${}()|[\\]".contains(c) { out.append("\\") }
        out.append(c)
    }
    return out
}

// MARK: - Strategy resolution (ported from strategyResolution)

struct ProxyResolvedStrategy {
    var regions: [String]
    var members: [String]
    var uses: [String]
    var filter: String
    var keywords: [String]
}

func proxySelectedSubscriptionIDs(_ group: ProxyStrategy, in config: ConfigData) -> [String] {
    if group.autoAllSubscriptions { return config.subscriptions.map { $0.id } }
    if !group.sourceSubscriptions.isEmpty { return group.sourceSubscriptions }
    // Legacy fallback: the page's `uses` name lines.
    let legacy = proxyLinesFrom(group.uses)
    return config.subscriptions.filter { legacy.contains($0.name) || legacy.contains(proxySubscriptionKey($0)) }.map { $0.id }
}

func proxySelectedNodeIDs(_ group: ProxyStrategy, in config: ConfigData) -> [String] {
    if group.autoAllNodes {
        let regions = proxyRegionKeys(group.regions)
        return config.nodeLinks.filter { node in
            let parsed = parseProxyNodeLink(node.url, node.name)
            return parsed.ok && !regions.isEmpty && proxyMatchesRegions(parsed.name, keys: regions)
        }.map { $0.id }
    }
    return group.nodeSources
}

func proxyResolveStrategy(_ group: ProxyStrategy, in config: ConfigData) -> ProxyResolvedStrategy {
    var manualTerms = proxyLinesFrom(group.members)
    let wantsProxy = group.includeProxy || manualTerms.contains("Proxy")
    manualTerms.removeAll { $0 == "Proxy" }
    let regions = proxyRegionKeys(group.regions)
    var matchedMembers: [String] = []
    let policyNames = ["DIRECT", "REJECT"] + config.strategies.map { $0.name }
    let parsedNodes = config.nodeLinks.compactMap { node -> (id: String, parsed: ParsedProxyNode)? in
        let parsed = parseProxyNodeLink(node.url, node.name)
        return parsed.ok ? (node.id, parsed) : nil
    }
    let subscriptionIDs = proxySelectedSubscriptionIDs(group, in: config)
    let uses = config.subscriptions.filter { subscriptionIDs.contains($0.id) }.map { $0.name }
    let nodeIDs = proxySelectedNodeIDs(group, in: config)
    for entry in parsedNodes where nodeIDs.contains(entry.id) {
        matchedMembers.append(entry.parsed.name)
    }
    var keywordTerms: [String] = []
    for term in manualTerms {
        if policyNames.contains(term) {
            matchedMembers.append(term)
            continue
        }
        let lower = term.lowercased()
        let localMatches = parsedNodes.filter { $0.parsed.name.lowercased().contains(lower) }
        if !localMatches.isEmpty {
            localMatches.forEach { matchedMembers.append($0.parsed.name) }
        } else if uses.isEmpty {
            matchedMembers.append(term)
        }
        keywordTerms.append(term)
    }
    if wantsProxy && group.name != "Proxy" {
        matchedMembers.append("Proxy")
    }
    let patterns = proxyRegionDefs(regions).map { $0.pattern } + keywordTerms.map(proxyRegexEscape)
    let filter = patterns.isEmpty ? group.customFilter : "(?i)(" + patterns.joined(separator: "|") + ")"
    return ProxyResolvedStrategy(
        regions: regions,
        members: proxyUniqueValues(matchedMembers),
        uses: proxyUniqueValues(uses),
        filter: filter,
        keywords: keywordTerms
    )
}

func proxyResolveUse(_ name: String, in config: ConfigData) -> String {
    if let found = config.subscriptions.first(where: { $0.name == name }) {
        return proxySubscriptionKey(found)
    }
    return name.trimmingCharacters(in: .whitespaces)
}

// MARK: - Clash YAML generation (ported from generate)

struct ProxyGeneratedOutput {
    var text: String
    var warnings: [String]
}

func proxyGenerateClash(_ config: ConfigData) -> ProxyGeneratedOutput {
    var out = proxyBaseConfig
    var warnings: [String] = []
    var parsedNodes: [ParsedProxyNode] = []
    for link in config.nodeLinks {
        let parsed = parseProxyNodeLink(link.url, link.name)
        if parsed.ok {
            parsedNodes.append(parsed)
        } else {
            warnings.append("节点「\(parsed.name)」未写入 YAML：\(parsed.error ?? "")")
        }
    }
    if !config.subscriptions.isEmpty {
        out.append("proxy-providers:")
        for sub in config.subscriptions {
            let key = proxySubscriptionKey(sub)
            out.append("  # 订阅名称: \(sub.name)")
            out.append("  " + proxyYamlQuote(key) + ":")
            out.append("    type: http")
            out.append("    url: " + proxyYamlQuote(sub.url))
            out.append("    path: " + proxyYamlQuote("./providers/\(key).yaml"))
            out.append("    interval: \(sub.interval)")
            out.append("    health-check:")
            out.append("      enable: true")
            out.append("      url: https://www.gstatic.com/generate_204")
            out.append("      interval: 300")
        }
        out.append("")
    }
    if !parsedNodes.isEmpty {
        out.append("proxies:")
        for node in parsedNodes {
            out.append(contentsOf: proxyNodeYaml(node))
        }
        out.append("")
    }
    out.append("proxy-groups:")
    out.append("  - name: " + proxyYamlQuote("Proxy"))
    out.append("    type: select")
    if !parsedNodes.isEmpty {
        out.append("    proxies:")
        for node in parsedNodes {
            out.append("      - " + proxyYamlQuote(node.name))
        }
    }
    if !config.subscriptions.isEmpty {
        out.append("    use:")
        for sub in config.subscriptions {
            out.append("      - " + proxyYamlQuote(proxySubscriptionKey(sub)))
        }
    }
    if parsedNodes.isEmpty && config.subscriptions.isEmpty {
        out.append("    proxies: []")
        warnings.append("Proxy 策略组还没有具体节点或订阅来源。")
    }
    for group in config.strategies {
        let resolved = proxyResolveStrategy(group, in: config)
        let members = resolved.members
        let uses = resolved.uses
        out.append("  - name: " + proxyYamlQuote(group.name))
        out.append("    type: " + group.type)
        if group.autoAllSubscriptions {
            out.append("    # 订阅来源: 自动全选（新增订阅自动加入）")
        }
        if group.autoAllNodes {
            out.append("    # 单个节点来源: 按地区自动匹配（新增节点自动加入匹配）")
        }
        let dialer = group.dialerProxy.trimmingCharacters(in: .whitespaces)
        if !dialer.isEmpty {
            out.append("    dialer-proxy: " + proxyYamlQuote(dialer))
            if dialer == group.name {
                warnings.append("策略「\(group.name)」的前置代理不能指向自己，否则会形成循环。")
            }
        }
        if !resolved.regions.isEmpty {
            out.append("    # 地区匹配: " + proxyRegionLabels(resolved.regions).joined(separator: "、"))
        }
        if !members.isEmpty {
            out.append("    proxies:")
            for member in members {
                out.append("      - " + proxyYamlQuote(member))
            }
        }
        if !uses.isEmpty {
            out.append("    use:")
            for use in uses {
                out.append("      - " + proxyYamlQuote(proxyResolveUse(use, in: config)))
            }
            if !resolved.filter.isEmpty {
                out.append("    filter: " + proxyYamlQuote(resolved.filter))
            }
        }
        if members.isEmpty && uses.isEmpty {
            out.append("    proxies: []")
            warnings.append(resolved.regions.isEmpty
                ? "策略「\(group.name)」还没有成员或订阅来源。"
                : "策略「\(group.name)」没有可供地区匹配的节点来源。")
        }
        if group.type != "select" {
            out.append("    url: https://www.gstatic.com/generate_204")
            out.append("    interval: 300")
        }
    }
    out.append("")
    if !config.providers.isEmpty {
        out.append("rule-providers:")
        for provider in config.providers {
            let providerName = provider.name.trimmingCharacters(in: .whitespaces)
            let displayName = providerName.isEmpty ? provider.key : providerName
            out.append("  " + proxyYamlQuote(displayName) + ":")
            out.append("    type: http")
            out.append("    behavior: " + provider.behavior)
            out.append("    format: yaml")
            out.append("    url: " + proxyYamlQuote(provider.url))
            out.append("    path: " + proxyYamlQuote("./ruleset/\(displayName).yaml"))
            out.append("    interval: 86400")
        }
        out.append("")
    }
    out.append("rules:")
    for provider in config.providers {
        let providerName = provider.name.trimmingCharacters(in: .whitespaces)
        let displayName = providerName.isEmpty ? provider.key : providerName
        out.append("  # \(provider.name)")
        out.append("  - RULE-SET,\(displayName),\(provider.policy)")
    }
    for rule in config.rules {
        var line = "  - " + rule.kind
        if rule.kind != "MATCH" { line += "," + rule.value }
        line += "," + rule.policy
        if rule.noResolve && (rule.kind.hasPrefix("IP-") || rule.kind.hasPrefix("GEOIP")) {
            line += ",no-resolve"
        }
        out.append(line)
    }
    out.append("  # CN 国内流量")
    out.append("  - GEOIP,CN,\(config.fallback.cn),no-resolve")
    out.append("  # 默认兜底")
    out.append("  - MATCH,\(config.fallback.defaultPolicy)")
    return ProxyGeneratedOutput(text: out.joined(separator: "\n"), warnings: warnings)
}

// MARK: - Shadowrocket .conf generation (ported from generateShadowrocket)

func proxySRSafe(_ value: String) -> String {
    value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: ",", with: "，").trimmingCharacters(in: .whitespaces)
}

func proxySRNode(_ node: ParsedProxyNode) -> String {
    let name = proxySRSafe(node.name)
    var head = "\(name) = \(node.protocolName), \(proxySRSafe(node.server)), \(node.port)"
    var fields: [String] = []
    switch node.protocolName {
    case "ss":
        fields.append("encrypt-method=" + proxySRSafe(node.cipher))
        fields.append("password=" + proxySRSafe(node.password))
        fields.append("udp-relay=true")
    case "vmess":
        fields.append("username=" + proxySRSafe(node.uuid))
        fields.append("alterId=\(node.alterId)")
        fields.append("method=" + proxySRSafe(node.cipher.isEmpty ? "auto" : node.cipher))
        if node.tls { fields.append("tls=true") }
        if !node.sni.isEmpty { fields.append("server-name=" + proxySRSafe(node.sni)) }
        if node.network == "ws" {
            fields.append("ws=true")
            if !node.path.isEmpty { fields.append("ws-path=" + proxySRSafe(node.path)) }
            if !node.host.isEmpty { fields.append("ws-headers=Host:" + proxySRSafe(node.host)) }
        }
        fields.append("udp-relay=true")
    case "trojan":
        fields.append("password=" + proxySRSafe(node.password))
        if !node.sni.isEmpty { fields.append("sni=" + proxySRSafe(node.sni)) }
        if node.skipCertVerify { fields.append("skip-cert-verify=true") }
        fields.append("udp-relay=true")
    case "vless":
        fields.append("username=" + proxySRSafe(node.uuid))
        if node.tls { fields.append("tls=true") }
        if !node.sni.isEmpty { fields.append("server-name=" + proxySRSafe(node.sni)) }
        if !node.flow.isEmpty { fields.append("flow=" + proxySRSafe(node.flow)) }
        if node.network == "ws" {
            fields.append("ws=true")
            if !node.path.isEmpty { fields.append("ws-path=" + proxySRSafe(node.path)) }
            if !node.host.isEmpty { fields.append("ws-headers=Host:" + proxySRSafe(node.host)) }
        }
        if node.reality {
            if !node.publicKey.isEmpty { fields.append("reality-public-key=" + proxySRSafe(node.publicKey)) }
            if !node.shortId.isEmpty { fields.append("reality-short-id=" + proxySRSafe(node.shortId)) }
            if !node.clientFingerprint.isEmpty { fields.append("reality-fingerprint=" + proxySRSafe(node.clientFingerprint)) }
        }
        if node.skipCertVerify { fields.append("skip-cert-verify=true") }
        fields.append("udp-relay=true")
    case "hysteria2":
        fields.append("password=" + proxySRSafe(node.password))
        if !node.sni.isEmpty { fields.append("sni=" + proxySRSafe(node.sni)) }
        if node.skipCertVerify { fields.append("skip-cert-verify=true") }
        fields.append("udp-relay=true")
    default:
        break
    }
    if !fields.isEmpty { head += ", " + fields.joined(separator: ", ") }
    return head
}

func proxySRGroupLine(_ group: ProxyStrategy, parsedNodes: [ParsedProxyNode], isBuiltin: Bool, resolved: ProxyResolvedStrategy, config: ConfigData) -> String {
    let name = proxySRSafe(group.name)
    let type = isBuiltin ? "select" : group.type
    var parts = ["\(name) = \(type)"]
    parts.append(contentsOf: resolved.members.map(proxySRSafe))
    for useName in resolved.uses {
        if let sub = config.subscriptions.first(where: { $0.name == useName || proxySubscriptionKey($0) == useName }),
           !sub.url.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("url=" + sub.url.trimmingCharacters(in: .whitespaces))
        }
    }
    if resolved.members.isEmpty && resolved.uses.isEmpty {
        parts.append("DIRECT")
    }
    if !resolved.filter.isEmpty {
        parts.append("policy-regex-filter=" + resolved.filter)
    }
    if type == "url-test" {
        parts.append(contentsOf: ["interval=600", "tolerance=100", "timeout=5"])
    }
    if type == "fallback" || type == "load-balance" {
        parts.append(contentsOf: ["interval=600", "timeout=5"])
    }
    return parts.joined(separator: ", ")
}

func proxyGenerateShadowrocket(_ config: ConfigData) -> ProxyGeneratedOutput {
    var out = [
        "# Shadowrocket 完整配置 · 由本页生成",
        "",
        "[General]",
        "bypass-system = true",
        "skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, localhost, *.local, captive.apple.com",
        "dns-server = 223.5.5.5, 119.29.29.29",
        "ipv6 = false",
        "",
        "[Proxy]",
    ]
    let parsedNodes = config.nodeLinks.compactMap { link -> ParsedProxyNode? in
        let parsed = parseProxyNodeLink(link.url, link.name)
        return parsed.ok ? parsed : nil
    }
    if !parsedNodes.isEmpty {
        parsedNodes.forEach { out.append(proxySRNode($0)) }
    } else {
        out.append("# 无单条节点；机场订阅会在策略组中引用")
    }
    out.append("")
    out.append("[Proxy Group]")
    let builtinResolved = ProxyResolvedStrategy(
        regions: [], members: parsedNodes.map { $0.name },
        uses: config.subscriptions.map { $0.name }, filter: "", keywords: []
    )
    let builtinGroup = ProxyStrategy(
        id: "", name: "Proxy", type: "select", members: "", uses: "",
        sourceSubscriptions: [], nodeSources: [], regions: [], customFilter: "",
        dialerProxy: "", includeProxy: false, autoAllSubscriptions: false, autoAllNodes: false
    )
    out.append(proxySRGroupLine(builtinGroup, parsedNodes: parsedNodes, isBuiltin: true, resolved: builtinResolved, config: config))
    for group in config.strategies {
        let resolved = proxyResolveStrategy(group, in: config)
        out.append(proxySRGroupLine(group, parsedNodes: parsedNodes, isBuiltin: false, resolved: resolved, config: config))
    }
    out.append("")
    out.append("[Rule]")
    for provider in config.providers {
        out.append("# " + proxySRSafe(provider.name))
        out.append("RULE-SET," + provider.url.trimmingCharacters(in: .whitespaces) + "," + proxySRSafe(provider.policy))
    }
    for rule in config.rules {
        let kind = rule.kind == "MATCH" ? "FINAL" : rule.kind
        var line = kind
        if kind != "FINAL" { line += "," + rule.value.trimmingCharacters(in: .whitespaces) }
        line += "," + proxySRSafe(rule.policy)
        if rule.noResolve && (rule.kind.hasPrefix("IP-") || rule.kind.hasPrefix("GEOIP")) {
            line += ",no-resolve"
        }
        out.append(line)
    }
    out.append("# CN 国内流量")
    out.append("GEOIP,CN," + proxySRSafe(config.fallback.cn) + ",no-resolve")
    out.append("# 默认兜底")
    out.append("FINAL," + proxySRSafe(config.fallback.defaultPolicy))
    out.append("")
    out.append("[Host]")
    out.append("localhost = 127.0.0.1")
    var notes: [String] = []
    if config.strategies.contains(where: { !$0.dialerProxy.trimmingCharacters(in: .whitespaces).isEmpty }) {
        notes.append("前置代理 dialer-proxy 是 Clash / Mihomo 字段，不写入 Shadowrocket 配置。")
    }
    return ProxyGeneratedOutput(text: out.joined(separator: "\n"), warnings: notes)
}

// MARK: - Repo search (ported from repoSearchResults)

func proxyRepoSearchKey(_ value: String) -> String {
    value.lowercased().components(separatedBy: CharacterSet(charactersIn: " \t._+-/")).joined()
}

func proxyRepoRuleURL(_ slug: String, shadowrocket: Bool) -> String {
    shadowrocket
        ? "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/\(slug)/\(slug).list"
        : "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/\(slug)/\(slug).yaml"
}

func proxyRepoSearchResults(_ query: String) -> [RepoRule] {
    let key = proxyRepoSearchKey(query)
    if key.isEmpty {
        let featured = ["OpenAI", "Google", "YouTube", "Netflix", "Telegram", "TikTok", "GitHub", "BiliBili"]
        return featured.compactMap { slug in repoRuleCatalog.first { $0.slug == slug } }
    }
    struct Scored { let item: RepoRule; let score: Int }
    let scored = repoRuleCatalog.compactMap { item -> Scored? in
        let name = proxyRepoSearchKey(item.slug)
        let category = proxyRepoSearchKey(item.category)
        let aliases = proxyRepoSearchKey(item.aliases)
        let score: Int
        if name == key { score = 0 }
        else if name.hasPrefix(key) { score = 1 }
        else if aliases.contains(key) { score = 2 }
        else if name.contains(key) { score = 3 }
        else if category.contains(key) { score = 4 }
        else { return nil }
        return Scored(item: item, score: score)
    }
    return scored.sorted {
        if $0.score != $1.score { return $0.score < $1.score }
        return $0.item.slug < $1.item.slug
    }.prefix(12).map { $0.item }
}
