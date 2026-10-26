import Foundation
import SwiftData

/// One saved proxy-rule config. The whole generator state lives
/// in `payload` as JSON-encoded ConfigData; the editor decodes
/// a draft, edits it, and encodes back on save. Identity comes
/// from SwiftData's persistentIdentifier.
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

    var decoded: ConfigData {
        get { proxyDecodeConfig(payload) }
        set { payload = proxyEncodeConfig(newValue) }
    }
}

/// Seed configs, decoded from the generated JSON constants.
/// 通用 = the page's general Clash config, 自用 = the page's
/// MINE preset. The user confirmed on 2026-10-26 that shipping
/// both presets in this public repo is fine.
func makeProxySeedConfigs() -> [(name: String, data: ConfigData)] {
    var out: [(name: String, data: ConfigData)] = []
    if let generalData = ProxySeedData.generalJSON.data(using: .utf8),
       let general = try? JSONDecoder().decode(ConfigData.self, from: generalData) {
        out.append(("通用", general))
    }
    if let mineData = ProxySeedData.mineJSON.data(using: .utf8),
       let mine = try? JSONDecoder().decode(ConfigData.self, from: mineData) {
        out.append(("自用", mine))
    }
    return out
}
