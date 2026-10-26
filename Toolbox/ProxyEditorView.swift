import SwiftUI
import SwiftData

/// Editor for one ProxyConfig. Works on a decoded draft; Save
/// encodes it back into the config. Navigation to the output
/// screen passes the draft binding, so unsaved edits still
/// generate, and an import replace writes back through it.
struct ProxyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let config: ProxyConfig
    @State private var draft: ConfigData
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

    init(config: ProxyConfig) {
        self.config = config
        _draft = State(initialValue: config.decoded)
    }

    var body: some View {
        Form {
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
                ProxyRepoSearchView(config: $draft)
                if draft.providers.isEmpty {
                    Text("暂无在线规则集。添加后会生成 rule-providers 与 RULE-SET 引用。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                ForEach(draft.providers) { provider in
                    ProxyEditorRow(
                        title: provider.name,
                        subtitle: "RULE-SET · \(provider.behavior) · \(provider.policy)",
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
            ProxyOutputView(draft: $draft, configName: config.name)
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
            ProxyProviderSheet(draft: $draft, existing: nil)
        }
        .sheet(item: $editingProvider) { provider in
            ProxyProviderSheet(draft: $draft, existing: provider)
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

    private func save() {
        config.payload = proxyEncodeConfig(draft)
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
