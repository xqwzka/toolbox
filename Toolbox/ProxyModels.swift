import Foundation

/// Native port of the generator page's state shape. Payloads are
/// JSON-encoded ConfigData stored in ProxyConfig.payload; the
/// editor works on a decoded draft and encodes back on save.
/// Field names mirror the page's JSON so seed/import payloads
/// decode without translation. IDs are the page's item ids
/// (stable row identity for reorder/delete).

struct ProxySubscription: Codable, Identifiable, Equatable {
    var id: String
    var key: String
    var name: String
    var url: String
    var interval: Int
}

struct ProxyNodeLink: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
}

struct ProxyStrategy: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: String
    var members: String
    var uses: String
    var sourceSubscriptions: [String]
    var nodeSources: [String]
    var regions: [String]
    var customFilter: String
    var dialerProxy: String
    var includeProxy: Bool
    var autoAllSubscriptions: Bool
    var autoAllNodes: Bool
}

struct ProxyProvider: Codable, Identifiable, Equatable {
    var id: String
    var key: String
    var name: String
    var url: String
    var behavior: String
    var policy: String
}

struct ProxyRule: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: String
    var value: String
    var policy: String
    var noResolve: Bool
}

struct ProxyFallback: Codable, Equatable {
    var cn: String
    var defaultPolicy: String

    enum CodingKeys: String, CodingKey {
        case cn
        case defaultPolicy = "default"
    }
}

struct ConfigData: Codable, Equatable {
    var subscriptions: [ProxySubscription]
    var nodeLinks: [ProxyNodeLink]
    var strategies: [ProxyStrategy]
    var providers: [ProxyProvider]
    var rules: [ProxyRule]
    var fallback: ProxyFallback
}

/// Static catalog entries (generated file ProxyCatalog.swift).
struct RepoRule {
    let slug: String
    let category: String
    let aliases: String
}

/// Static region entry (generated file ProxyStaticData.swift).
struct RegionDef {
    let key: String
    let label: String
    let pattern: String
}

// MARK: - Tolerant decoding

/// Decoders that fall back to a default instead of failing the
/// whole config when one field is missing or mistyped. Payloads
/// are only ever written by this app, but a single bad field
/// must not wipe a user's saved config.
extension KeyedDecodingContainer {
    func decodeOrDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        if let nested = try? decodeIfPresent(T.self, forKey: key), let value = nested {
            return value
        }
        return defaultValue
    }
}

extension ProxySubscription {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOrDefault(String.self, forKey: .id, default: newProxyID())
        key = c.decodeOrDefault(String.self, forKey: .key, default: "")
        name = c.decodeOrDefault(String.self, forKey: .name, default: "")
        url = c.decodeOrDefault(String.self, forKey: .url, default: "")
        interval = c.decodeOrDefault(Int.self, forKey: .interval, default: 86400)
    }
}

extension ProxyNodeLink {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOrDefault(String.self, forKey: .id, default: newProxyID())
        name = c.decodeOrDefault(String.self, forKey: .name, default: "")
        url = c.decodeOrDefault(String.self, forKey: .url, default: "")
    }
}

extension ProxyStrategy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOrDefault(String.self, forKey: .id, default: newProxyID())
        name = c.decodeOrDefault(String.self, forKey: .name, default: "")
        type = c.decodeOrDefault(String.self, forKey: .type, default: "select")
        members = c.decodeOrDefault(String.self, forKey: .members, default: "")
        uses = c.decodeOrDefault(String.self, forKey: .uses, default: "")
        sourceSubscriptions = c.decodeOrDefault([String].self, forKey: .sourceSubscriptions, default: [])
        nodeSources = c.decodeOrDefault([String].self, forKey: .nodeSources, default: [])
        regions = c.decodeOrDefault([String].self, forKey: .regions, default: [])
        customFilter = c.decodeOrDefault(String.self, forKey: .customFilter, default: "")
        dialerProxy = c.decodeOrDefault(String.self, forKey: .dialerProxy, default: "")
        includeProxy = c.decodeOrDefault(Bool.self, forKey: .includeProxy, default: false)
        autoAllSubscriptions = c.decodeOrDefault(Bool.self, forKey: .autoAllSubscriptions, default: false)
        autoAllNodes = c.decodeOrDefault(Bool.self, forKey: .autoAllNodes, default: false)
    }
}

extension ProxyProvider {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOrDefault(String.self, forKey: .id, default: newProxyID())
        key = c.decodeOrDefault(String.self, forKey: .key, default: "")
        name = c.decodeOrDefault(String.self, forKey: .name, default: "")
        url = c.decodeOrDefault(String.self, forKey: .url, default: "")
        behavior = c.decodeOrDefault(String.self, forKey: .behavior, default: "classical")
        policy = c.decodeOrDefault(String.self, forKey: .policy, default: "Proxy")
    }
}

extension ProxyRule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOrDefault(String.self, forKey: .id, default: newProxyID())
        name = c.decodeOrDefault(String.self, forKey: .name, default: "")
        kind = c.decodeOrDefault(String.self, forKey: .kind, default: "")
        value = c.decodeOrDefault(String.self, forKey: .value, default: "")
        policy = c.decodeOrDefault(String.self, forKey: .policy, default: "Proxy")
        noResolve = c.decodeOrDefault(Bool.self, forKey: .noResolve, default: false)
    }
}

extension ProxyFallback {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cn = c.decodeOrDefault(String.self, forKey: .cn, default: "DIRECT")
        defaultPolicy = c.decodeOrDefault(String.self, forKey: .defaultPolicy, default: "Proxy")
    }
}

extension ConfigData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = c.decodeOrDefault([ProxySubscription].self, forKey: .subscriptions, default: [])
        nodeLinks = c.decodeOrDefault([ProxyNodeLink].self, forKey: .nodeLinks, default: [])
        strategies = c.decodeOrDefault([ProxyStrategy].self, forKey: .strategies, default: [])
        providers = c.decodeOrDefault([ProxyProvider].self, forKey: .providers, default: [])
        rules = c.decodeOrDefault([ProxyRule].self, forKey: .rules, default: [])
        fallback = c.decodeOrDefault(ProxyFallback.self, forKey: .fallback, default: ProxyFallback(cn: "DIRECT", defaultPolicy: "Proxy"))
    }
}

// MARK: - Shared helpers (ported from the page)

func newProxyID() -> String {
    UUID().uuidString.lowercased()
}

/// Split on newlines or commas, trim, drop empties.
func proxyLinesFrom(_ s: String) -> [String] {
    s.components(separatedBy: CharacterSet(charactersIn: "\n,"))
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

func proxyUniqueValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values where !seen.contains(value) {
        seen.insert(value)
        out.append(value)
    }
    return out
}

/// Single-quote a YAML scalar, doubling inner quotes.
func proxyYamlQuote(_ v: String) -> String {
    "'" + v.replacingOccurrences(of: "'", with: "''") + "'"
}

/// Subscription display key: the page writes the name as the
/// provider key (key falls back to name, then a generic word).
func proxySubscriptionKey(_ sub: ProxySubscription) -> String {
    // Matches the page exactly: a whitespace-only name is
    // truthy in JS, so it trims to empty and falls back to 订阅
    // rather than to the key.
    let candidate = !sub.name.isEmpty ? sub.name : (!sub.key.isEmpty ? sub.key : "订阅")
    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "订阅" : trimmed
}

/// Blank config: the page's blankConfig + four region groups,
/// which is also what a freshly created config starts from.
func blankProxyConfig() -> ConfigData {
    ConfigData(
        subscriptions: [],
        nodeLinks: [],
        strategies: defaultRegionStrategies(),
        providers: [],
        rules: [],
        fallback: ProxyFallback(cn: "DIRECT", defaultPolicy: "Proxy")
    )
}

func defaultRegionStrategies() -> [ProxyStrategy] {
    [
        ("香港", "HK"), ("日本", "JP"), ("美国", "US"), ("新加坡", "SG"),
    ].map { name, region in
        ProxyStrategy(
            id: newProxyID(), name: name, type: "select", members: "", uses: "",
            sourceSubscriptions: [], nodeSources: [], regions: [region], customFilter: "",
            dialerProxy: "", includeProxy: false,
            autoAllSubscriptions: true, autoAllNodes: true
        )
    }
}

/// All policies a rule or provider may point at: builtins plus
/// the config's own strategy names.
func proxyAvailablePolicies(_ config: ConfigData) -> [String] {
    ["Proxy", "DIRECT", "REJECT"] + config.strategies.map { $0.name }
}

func proxyEncodeConfig(_ config: ConfigData) -> Data {
    (try? JSONEncoder().encode(config)) ?? Data()
}

func proxyDecodeConfig(_ data: Data) -> ConfigData {
    (try? JSONDecoder().decode(ConfigData.self, from: data)) ?? blankProxyConfig()
}
