import Foundation
import SwiftData

/// One saved proxy-rule config. The whole generator state lives
/// in `payload` as JSON-encoded ProxyDualConfig: a Clash side
/// and a Shadowrocket side under one name, plus which side the
/// editor last showed. Identity comes from SwiftData's
/// persistentIdentifier.
@Model
final class ProxyConfig {
    var name: String
    var updatedAt: Date
    var payload: Data

    init(name: String, updatedAt: Date = Date(), payload: Data) {
        self.name = name
        self.updatedAt = updatedAt
        self.payload = payload
    }

    var decoded: ProxyDualConfig {
        get { proxyDecodeDualConfig(payload) }
        set { payload = proxyEncodeDualConfig(newValue) }
    }
}

/// Seed configs, decoded from the generated JSON constants.
/// 通用 = the page's general Clash config, 自用 = the page's
/// MINE preset — both as the Clash side, with an empty
/// Shadowrocket side, exactly like the page's empty SR slots.
/// The user confirmed on 2026-10-26 that shipping both presets
/// in this public repo is fine.
func makeProxySeedConfigs() -> [(name: String, data: ProxyDualConfig)] {
    var out: [(name: String, data: ProxyDualConfig)] = []
    if let generalData = ProxySeedData.generalJSON.data(using: .utf8),
       let general = try? JSONDecoder().decode(ConfigData.self, from: generalData) {
        out.append(("通用", ProxyDualConfig(clash: general)))
    }
    if let mineData = ProxySeedData.mineJSON.data(using: .utf8),
       let mine = try? JSONDecoder().decode(ConfigData.self, from: mineData) {
        out.append(("自用", ProxyDualConfig(clash: mine)))
    }
    return out
}
