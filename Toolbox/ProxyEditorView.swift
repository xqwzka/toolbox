import SwiftUI
import SwiftData

/// Editor for one ProxyConfig. Works on a decoded draft; Save
/// encodes it back into the config. Navigation to the output
/// screen passes the draft binding, so unsaved edits still
/// generate, and an import replace writes back through it.
struct ProxyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let config: ProxyConfig
    /// The side currently being edited. The other side lives in
    /// its own draft and is flushed back on switch and on save,
    /// so the two softwares never share rules.
    @State private var draft: ConfigData
    @State private var clashDraft: ConfigData
    @State private var srDraft: ConfigData
    @State private var software: ProxySoftware
    @State private var savedNote = false

    @State private var editingSubscription: ProxySubscription?
    @State private var addingSubscription = false
    @State private var editingNode: ProxyNodeLink?
    @State private var addingNode = false
    @State private var editingStrategy: ProxyStrategy?
    @State private var addingStrategy = false
    @State private var editingProvider: ProxyProvider?
    @State private var addingProvider = false
    @State private var editingRule: ProxyRule?
    @State private var showingBatch = false
    @State private var showingOutput = false
    @State private var showingImport = false

    init(config: ProxyConfig) {
        self.config = config
        let dual = config.decoded
        _clashDraft = State(initialValue: dual.clash)
        _srDraft = State(initialValue: dual.shadowrocket)
        _software = State(initialValue: dual.software)
        _draft = State(initialValue: dual.software == .shadowrocket ? dual.shadowrocket : dual.clash)
    }

    var body: some View {
        Form {
            Section {
                Picker("代理软件", selection: $software) {
                    Text("Clash / Mihomo").tag(ProxySoftware.clash)
                    Text("Shadowrocket").tag(ProxySoftware.shadowrocket)
                }
                .pickerStyle(.segmented)
                .onChange(of: software) { old, new in
                    if old == .shadowrocket { srDraft = draft } else { clashDraft = draft }
                    draft = new == .shadowrocket ? srDraft : clashDraft
                }
                Text(software == .shadowrocket
                    ? "正在编辑 Shadowrocket 专用规则；在线规则集使用 .list，配置与 Clash / Mihomo 完全独立。"
                    : "正在编辑 Clash / Mihomo 专用规则；在线规则集使用 YAML，配置与 Shadowrocket 完全独立。")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section("通用") {
                Toggle("IPv6", isOn: $draft.ipv6)
                Text(software == .shadowrocket
                    ? "生成时写入 [General] 的 ipv6。"
                    : "生成时顶层 ipv6 与 DNS ipv6 都跟这个开关。")
                    .font(.caption)
                    .foregroundColor(.gray)
                Button("导入配置") { showingImport = true }
                Text("粘贴 Clash YAML 或 Shadowrocket .conf，识别格式后替换对应一侧的配置，导入后自动切到那一侧。")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section("节点") {
                if draft.subscriptions.isEmpty && draft.nodeLinks.isEmpty {
                    Text("还没有节点来源。可添加机场订阅，或单个 ss / vmess / trojan / vless / hysteria2 链接。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                ForEach(draft.subscriptions) { sub in
                    ProxyEditorRow(
                        title: sub.name,
                        subtitle: "订阅 · \(sub.interval) 秒",
                        onEdit: { editingSubscription = sub },
                        onUp: { move(&draft.subscriptions, id: sub.id, delta: -1) },
                        onDown: { move(&draft.subscriptions, id: sub.id, delta: 1) },
                        onDelete: { draft.subscriptions.removeAll { $0.id == sub.id } }
                    )
                }
                ForEach(draft.nodeLinks) { node in
                    let parsed = parseProxyNodeLink(node.url, fallbackName: node.name)
                    ProxyEditorRow(
                        title: parsed.name,
                        subtitle: parsed.ok ? "单个节点 · \(parsed.protocolName)" : "未识别 · \(parsed.error ?? "")",
                        onEdit: { editingNode = node },
                        onUp: { move(&draft.nodeLinks, id: node.id, delta: -1) },
                        onDown: { move(&draft.nodeLinks, id: node.id, delta: 1) },
                        onDelete: { draft.nodeLinks.removeAll { $0.id == node.id } }
                    )
                }
                Button("添加订阅") { addingSubscription = true }
                Button("添加单条节点") { addingNode = true }
            }

            Section("策略组") {
                if draft.strategies.isEmpty {
                    Text("还没有自定义策略。规则仍可直接选择内置 Proxy、DIRECT 或 REJECT。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                ForEach(draft.strategies) { group in
                    let resolved = proxyResolveStrategy(group, in: draft)
                    let labels = proxyRegionLabels(resolved.regions)
                    ProxyEditorRow(
                        title: group.name,
                        subtitle: group.type + (labels.isEmpty ? "" : " · " + labels.joined(separator: " / "))
                            + (group.autoAllSubscriptions ? " · 自动全选订阅" : "")
                            + (group.autoAllNodes ? " · 地区匹配节点" : "")
                            + (group.dialerProxy.isEmpty ? "" : " · 前置 \(group.dialerProxy)"),
                        onEdit: { editingStrategy = group },
                        onUp: { move(&draft.strategies, id: group.id, delta: -1) },
                        onDown: { move(&draft.strategies, id: group.id, delta: 1) },
                        onDelete: { deleteStrategy(group) }
                    )
                }
                Button("添加策略") { addingStrategy = true }
            }

            Section("规则集") {
                ProxyRepoSearchView(config: $draft, shadowrocket: software == .shadowrocket)
                if draft.providers.isEmpty {
                    Text(software == .shadowrocket
                        ? "暂无 Shadowrocket 在线规则集。添加后会生成 .conf 中的 RULE-SET 引用。"
                        : "暂无在线规则集。添加后会生成 rule-providers 与 RULE-SET 引用。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                ForEach(draft.providers) { provider in
                    ProxyEditorRow(
                        title: provider.name,
                        subtitle: software == .shadowrocket
                            ? "RULE-SET · \(provider.policy)"
                            : "RULE-SET · \(provider.behavior) · \(provider.policy)",
                        onEdit: { editingProvider = provider },
                        onUp: { move(&draft.providers, id: provider.id, delta: -1) },
                        onDown: { move(&draft.providers, id: provider.id, delta: 1) },
                        onDelete: { draft.providers.removeAll { $0.id == provider.id } }
                    )
                }
                Button("手动添加规则集") { addingProvider = true }
            }

            Section("分流规则") {
                if draft.rules.isEmpty {
                    Text("暂无分流规则。CN 与默认兜底会自动生成。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                ForEach(draft.rules) { rule in
                    ProxyEditorRow(
                        title: rule.kind + (rule.value.isEmpty ? "" : " · \(rule.value)"),
                        subtitle: "\(rule.policy)" + (rule.noResolve ? " · no-resolve" : "") + (rule.name.isEmpty ? "" : " · \(rule.name)"),
                        onEdit: { editingRule = rule },
                        onUp: { move(&draft.rules, id: rule.id, delta: -1) },
                        onDown: { move(&draft.rules, id: rule.id, delta: 1) },
                        onDelete: { draft.rules.removeAll { $0.id == rule.id } }
                    )
                }
                Button("批量添加规则") { showingBatch = true }
            }

            Section("兜底分流") {
                Picker("CN 国内流量", selection: $draft.fallback.cn) {
                    ForEach(proxyAvailablePolicies(draft), id: \.self) { policy in
                        Text(policy).tag(policy)
                    }
                }
                Text("生成 GEOIP,CN 规则，默认 DIRECT。")
                    .font(.caption)
                    .foregroundColor(.gray)
                Picker("默认兜底", selection: $draft.fallback.defaultPolicy) {
                    ForEach(proxyAvailablePolicies(draft), id: \.self) { policy in
                        Text(policy).tag(policy)
                    }
                }
                Text("生成最后一条 MATCH 规则，默认 Proxy。")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle(config.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("生成") { showingOutput = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    save()
                    savedNote = true
                }
            }
        }
        .navigationDestination(isPresented: $showingOutput) {
            ProxyOutputView(draft: $draft, software: software, configName: config.name, onImportClash: { imported in
                clashDraft = imported
                if software == .clash { draft = imported }
            }, onImportShadowrocket: { imported in
                srDraft = imported
                if software == .shadowrocket { draft = imported }
            })
        }
        .sheet(isPresented: $showingImport) {
            ProxyImportSheet { imported, side in
                applyImport(imported, side: side)
                showingImport = false
            }
        }
        .onDisappear(perform: save)
        .sheet(isPresented: $addingSubscription) {
            ProxySubscriptionSheet(draft: $draft, existing: nil)
        }
        .sheet(item: $editingSubscription) { sub in
            ProxySubscriptionSheet(draft: $draft, existing: sub)
        }
        .sheet(isPresented: $addingNode) {
            ProxyNodeSheet(draft: $draft, existing: nil)
        }
        .sheet(item: $editingNode) { node in
            ProxyNodeSheet(draft: $draft, existing: node)
        }
        .sheet(isPresented: $addingStrategy) {
            ProxyStrategySheet(draft: $draft, existing: nil)
        }
        .sheet(item: $editingStrategy) { group in
            ProxyStrategySheet(draft: $draft, existing: group)
        }
        .sheet(isPresented: $addingProvider) {
            ProxyProviderSheet(draft: $draft, existing: nil, shadowrocket: software == .shadowrocket)
        }
        .sheet(item: $editingProvider) { provider in
            ProxyProviderSheet(draft: $draft, existing: provider, shadowrocket: software == .shadowrocket)
        }
        .sheet(item: $editingRule) { rule in
            ProxyRuleSheet(draft: $draft, existing: rule)
        }
        .sheet(isPresented: $showingBatch) {
            ProxyBatchSheet(draft: $draft)
        }
        .alert("已保存", isPresented: $savedNote) {
            Button("好", role: .cancel) {}
        }
    }

    /// Import replaces one side and switches the editor to
    /// it, so the imported content is what the user sees.
    /// The current side's unsaved edits are flushed to its
    /// own draft first. For a cross-side import, only the
    /// software is changed here: onChange runs after this
    /// handler and loads the imported side's draft itself —
    /// setting draft here too would make that flush copy
    /// the imported content over the old side's draft.
    private func applyImport(_ imported: ConfigData, side: ProxySoftware) {
        if software == .shadowrocket { srDraft = draft } else { clashDraft = draft }
        if side == .shadowrocket { srDraft = imported } else { clashDraft = imported }
        if side == software {
            draft = imported
        } else {
            software = side
        }
    }

    private func save() {
        if software == .shadowrocket { srDraft = draft } else { clashDraft = draft }
        config.payload = proxyEncodeDualConfig(ProxyDualConfig(
            clash: clashDraft, shadowrocket: srDraft, software: software))
        config.updatedAt = Date()
        try? modelContext.save()
    }

    private func move<T: Identifiable>(_ array: inout [T], id: T.ID, delta: Int) {
        guard let i = array.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0 && j < array.count else { return }
        array.swapAt(i, j)
    }

    /// Deleting a strategy repoints everything that referenced
    /// it at Proxy, as the page does — otherwise rules would
    /// point at a group that no longer exists.
    private func deleteStrategy(_ group: ProxyStrategy) {
        proxyRepointPolicy(from: group.name, to: "Proxy", draft: &draft)
        draft.strategies.removeAll { $0.id == group.id }
    }
}

func proxyRepointPolicy(from: String, to: String, draft: inout ConfigData) {
    for i in draft.providers.indices where draft.providers[i].policy == from {
        draft.providers[i].policy = to
    }
    for i in draft.rules.indices where draft.rules[i].policy == from {
        draft.rules[i].policy = to
    }
    if draft.fallback.cn == from { draft.fallback.cn = to }
    if draft.fallback.defaultPolicy == from { draft.fallback.defaultPolicy = to }
    for i in draft.strategies.indices {
        if draft.strategies[i].dialerProxy == from {
            draft.strategies[i].dialerProxy = to == "Proxy" ? "" : to
        }
        draft.strategies[i].members = proxyLinesFrom(draft.strategies[i].members)
            .map { $0 == from ? to : $0 }
            .filter { $0 != "Proxy" }
            .joined(separator: "\n")
    }
}

private struct ProxyEditorRow: View {
    let title: String
    let subtitle: String
    let onEdit: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            Button(action: onDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}
