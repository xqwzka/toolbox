import SwiftUI
import SwiftData

/// Config list: multiple saved proxy-rule configs, as the user
/// asked. First launch seeds 通用 and 自用 from the page's
/// presets; afterwards the list is the user's own.
struct ProxyRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProxyConfig.updatedAt, order: .reverse) private var configs: [ProxyConfig]
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var renaming: ProxyConfig?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if configs.isEmpty {
                    ContentUnavailableView(
                        "还没有代理规则配置",
                        systemImage: "globe",
                        description: Text("新建一个配置，或等待预设载入。")
                    )
                } else {
                    List {
                        ForEach(configs) { config in
                            NavigationLink {
                                ProxyEditorView(config: config)
                            } label: {
                                ProxyConfigRow(config: config)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    modelContext.delete(config)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    duplicate(config)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                                Button {
                                    renaming = config
                                    renameText = config.name
                                } label: {
                                    Label("改名", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("代理规则")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建配置", isPresented: $showingAdd) {
                TextField("配置名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let config = ProxyConfig(name: name, payload: proxyEncodeConfig(blankProxyConfig()))
                    modelContext.insert(config)
                }
            }
            .alert("改名", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("配置名称", text: $renameText)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    guard let config = renaming else { return }
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        config.name = name
                        config.updatedAt = Date()
                    }
                    renaming = nil
                }
            }
            .onAppear(perform: seedIfNeeded)
        }
    }

    private func seedIfNeeded() {
        guard configs.isEmpty else { return }
        for seed in makeProxySeedConfigs() {
            modelContext.insert(ProxyConfig(name: seed.name, payload: proxyEncodeConfig(seed.data)))
        }
    }

    private func duplicate(_ config: ProxyConfig) {
        let copy = ProxyConfig(name: config.name + " 副本", payload: config.payload)
        modelContext.insert(copy)
    }
}

private struct ProxyConfigRow: View {
    let config: ProxyConfig

    var body: some View {
        let data = proxyDecodeConfig(config.payload)
        VStack(alignment: .leading, spacing: 4) {
            Text(config.name)
                .font(.headline)
            Text("\(data.strategies.count) 策略 · \(data.providers.count) 规则集 · \(data.rules.count) 分流规则 · \(data.subscriptions.count) 订阅 · \(data.nodeLinks.count) 节点")
                .font(.caption)
                .foregroundColor(.gray)
            Text("更新于 \(config.updatedAt, format: .dateTime.year().month().day().hour().minute())")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}
