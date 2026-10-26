import SwiftUI
import SwiftData

/// 工具箱: 记账 + 卡密 + 本地网页 in one app. All three keep
/// their own UI and their own data, all local-only: no account,
/// no sync, no network. The two SwiftData stores live in one
/// container; the web viewer keeps its loopback server and
/// non-persistent page store exactly as before.
@main
struct ToolboxApp: App {
    init() {
        // Record ObjC exceptions (e.g. AVFoundation validation
        // failures in the Live Photo writer) so the next launch
        // can show the real crash reason.
        installLiveCrashCapture()
    }

    private let container: ModelContainer = {
        let schema = Schema([LedgerRecord.self, CardCode.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建数据存储：\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ToolboxRootView()
        }
        .modelContainer(container)
    }
}
