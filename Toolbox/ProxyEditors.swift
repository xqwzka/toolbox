import SwiftUI

/// Item editors for the proxy editor, following the app's sheet
/// pattern (NavigationStack + init-seeded @State + save button).
/// Validation mirrors the page: duplicate names are rejected,
/// node adds must parse, strategy names may not be builtins.

// MARK: - Subscription

struct ProxySubscriptionSheet: View {
    @Binding var draft: ConfigData
    let existing: ProxySubscription?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @State private var intervalText: String
    @State private var error = ""

    init(draft: Binding<ConfigData>, existing: ProxySubscription?) {
        _draft = draft
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _intervalText = State(initialValue: existing.map { "\($0.interval)" } ?? "86400")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("订阅名称", text: $name)
                TextField("订阅 URL", text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("更新间隔（秒）", text: $intervalText)
                    .keyboardType(.numberPad)
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(existing == nil ? "添加订阅" : "编辑订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else {
            error = "名称和 URL 不能为空。"
            return
        }
        if draft.subscriptions.contains(where: { $0.name == trimmedName && $0.id != existing?.id }) {
            error = "订阅名称已存在，请换一个名称。"
            return
        }
        let interval = Int(intervalText) ?? 86400
        if let existing {
            if let index = draft.subscriptions.firstIndex(where: { $0.id == existing.id }) {
                draft.subscriptions[index].name = trimmedName
                draft.subscriptions[index].key = trimmedName
                draft.subscriptions[index].url = trimmedURL
                draft.subscriptions[index].interval = interval
            }
        } else {
            let id = newProxyID()
            draft.subscriptions.append(ProxySubscription(id: id, key: trimmedName, name: trimmedName, url: trimmedURL, interval: interval))
        }
        dismiss()
    }
}

// MARK: - Single node link

struct ProxyNodeSheet: View {
    @Binding var draft: ConfigData
    let existing: ProxyNodeLink?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @State private var error = ""

    init(draft: Binding<ConfigData>, existing: ProxyNodeLink?) {
        _draft = draft
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
    }

    private var parsed: ParsedProxyNode {
        parseProxyNodeLink(url, fallbackName: name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("节点名称（可选）", text: $name)
                TextField("分享链接", text: $url, axis: .vertical)
                    .lineLimit(3...6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text(parsed.ok ? "已识别 \(parsed.protocolName)" : (parsed.error ?? ""))
                    .font(.caption)
                    .foregroundColor(parsed.ok ? .gray : .red)
                Text("支持 ss、vmess、trojan、vless、hysteria2 分享链接。")
                    .font(.caption)
                    .foregroundColor(.gray)
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(existing == nil ? "添加单条节点" : "编辑节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else {
            error = "链接不能为空。"
            return
        }
        // Adding follows the page: an unparsed link is rejected.
        // Editing an existing row keeps the page's inline-edit
        // behavior and allows any text.
        if existing == nil && !parsed.ok {
            error = parsed.error ?? "链接无法识别。"
            return
        }
        if let existing {
            if let index = draft.nodeLinks.firstIndex(where: { $0.id == existing.id }) {
                draft.nodeLinks[index].name = trimmedName
                draft.nodeLinks[index].url = trimmedURL
            }
        } else {
            draft.nodeLinks.append(ProxyNodeLink(id: newProxyID(), name: trimmedName.isEmpty ? parsed.name : trimmedName, url: trimmedURL))
        }
        dismiss()
    }
}

// MARK: - Strategy

struct ProxyStrategySheet: View {
    @Binding var draft: ConfigData
    let existing: ProxyStrategy?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: String
    @State private var regions: [String]
    @State private var includeProxy: Bool
    @State private var includeDirect: Bool
    @State private var includeReject: Bool
    @State private var keywords: String
    @State private var autoAllSubscriptions: Bool
    @State private var autoAllNodes: Bool
    @State private var selectedSubscriptions: [String]
    @State private var selectedNodes: [String]
    @State private var dialerProxy: String
    @State private var error = ""

    init(draft: Binding<ConfigData>, existing: ProxyStrategy?) {
        _draft = draft
        self.existing = existing
        let lines = existing.map { proxyLinesFrom($0.members) } ?? []
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? "select")
        _regions = State(initialValue: existing?.regions ?? [])
        _includeProxy = State(initialValue: existing?.includeProxy ?? false)
        _includeDirect = State(initialValue: lines.contains("DIRECT"))
        _includeReject = State(initialValue: lines.contains("REJECT"))
        _keywords = State(initialValue: lines.filter { !["Proxy", "DIRECT", "REJECT"].contains($0) }.joined(separator: "\n"))
        _autoAllSubscriptions = State(initialValue: existing?.autoAllSubscriptions ?? false)
        _autoAllNodes = State(initialValue: existing?.autoAllNodes ?? false)
        _selectedSubscriptions = State(initialValue: existing?.sourceSubscriptions ?? [])
        _selectedNodes = State(initialValue: existing?.nodeSources ?? [])
        _dialerProxy = State(initialValue: existing?.dialerProxy ?? "")
    }

    private var resolvedPreview: String {
        var preview = ProxyStrategy(
            id: existing?.id ?? "", name: name, type: type,
            members: builtMembers(), uses: "",
            sourceSubscriptions: autoAllSubscriptions ? draft.subscriptions.map { $0.id } : selectedSubscriptions,
            nodeSources: selectedNodes,
            regions: regions, customFilter: "", dialerProxy: dialerProxy,
            includeProxy: includeProxy, autoAllSubscriptions: autoAllSubscriptions, autoAllNodes: autoAllNodes
        )
        // Preview against the draft with this strategy swapped in.
        var previewDraft = draft
        if let existing, let index = previewDraft.strategies.firstIndex(where: { $0.id == existing.id }) {
            previewDraft.strategies[index] = preview
        } else {
            previewDraft.strategies.append(preview)
            preview = previewDraft.strategies.last!
        }
        let resolved = proxyResolveStrategy(preview, in: previewDraft)
        var parts: [String] = []
        let labels = proxyRegionLabels(resolved.regions)
        if !labels.isEmpty {
            parts.append("地区：" + labels.joined(separator: "、"))
        }
        if !resolved.keywords.isEmpty {
            parts.append("关键字：" + resolved.keywords.joined(separator: "、"))
        }
        return parts.isEmpty ? "可选择订阅或单个节点；关键字仍支持节点名称包含匹配。" : parts.joined(separator: "；") + "。节点名称关键字保留包含匹配。"
    }

    private func builtMembers() -> String {
        var lines: [String] = []
        if includeDirect { lines.append("DIRECT") }
        if includeReject { lines.append("REJECT") }
        lines.append(contentsOf: proxyLinesFrom(keywords).filter { !["Proxy", "DIRECT", "REJECT"].contains($0) })
        return proxyUniqueValues(lines).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("策略名称", text: $name)
                    Picker("类型", selection: $type) {
                        Text("手动选择 select").tag("select")
                        Text("自动测速 url-test").tag("url-test")
                        Text("故障转移 fallback").tag("fallback")
                        Text("负载均衡 load-balance").tag("load-balance")
                    }
                }
                Section("按地区匹配节点") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(proxyRegionCatalog, id: \.key) { region in
                            let selected = regions.contains(region.key)
                            Button {
                                if selected {
                                    regions.removeAll { $0 == region.key }
                                } else {
                                    regions.append(region.key)
                                }
                            } label: {
                                Text("\(region.label) \(region.key)")
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? Color.blue : Color.gray.opacity(0.15))
                                    .foregroundColor(selected ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Toggle("Proxy（内置，排在最后）", isOn: $includeProxy)
                    Toggle("DIRECT（内置）", isOn: $includeDirect)
                    Toggle("REJECT（内置）", isOn: $includeReject)
                    Text(resolvedPreview)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Section("成员 / 节点关键字（每行一个）") {
                    TextEditor(text: $keywords)
                        .frame(minHeight: 80)
                    Text("节点名称继续支持包含匹配；勾选的单个节点不经过模糊匹配。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Section("节点来源") {
                    Toggle("自动全选订阅（新增订阅自动加入）", isOn: $autoAllSubscriptions)
                    Toggle("按地区自动匹配（新增节点自动加入匹配）", isOn: $autoAllNodes)
                    if !draft.subscriptions.isEmpty {
                        Text("订阅").font(.caption).foregroundColor(.gray)
                        ForEach(draft.subscriptions) { sub in
                            let checked = autoAllSubscriptions || selectedSubscriptions.contains(sub.id)
                            Button {
                                if selectedSubscriptions.contains(sub.id) {
                                    selectedSubscriptions.removeAll { $0 == sub.id }
                                } else {
                                    selectedSubscriptions.append(sub.id)
                                }
                            } label: {
                                HStack {
                                    Text(sub.name)
                                    Spacer()
                                    if checked { Image(systemName: "checkmark") }
                                }
                            }
                            .disabled(autoAllSubscriptions)
                            .buttonStyle(.plain)
                        }
                    }
                    if !draft.nodeLinks.isEmpty {
                        Text("单个节点").font(.caption).foregroundColor(.gray)
                        ForEach(draft.nodeLinks) { node in
                            let parsed = parseProxyNodeLink(node.url, fallbackName: node.name)
                            let checked = selectedNodes.contains(node.id)
                            Button {
                                if checked {
                                    selectedNodes.removeAll { $0 == node.id }
                                } else {
                                    selectedNodes.append(node.id)
                                }
                            } label: {
                                HStack {
                                    Text(parsed.ok ? parsed.name : (node.name.isEmpty ? "未识别节点" : node.name))
                                    Spacer()
                                    if checked { Image(systemName: "checkmark") }
                                }
                            }
                            .disabled(autoAllNodes)
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("前置代理（链式代理，可选）") {
                    TextField("不使用，留空即可", text: $dialerProxy)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("可填写另一个策略组或单条节点的精确名称；仅写入 Clash / Mihomo 的 dialer-proxy。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(proxyDialerSuggestions(draft: draft, excluding: name), id: \.self) { suggestion in
                                Button(suggestion) { dialerProxy = suggestion }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(existing == nil ? "添加策略" : "编辑策略")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            error = "策略名称不能为空。"
            return
        }
        if ["Proxy", "DIRECT", "REJECT"].contains(trimmedName) ||
            draft.strategies.contains(where: { $0.name == trimmedName && $0.id != existing?.id }) {
            error = "名称为空或与已有策略重复。"
            return
        }
        let members = builtMembers()
        let strategy = ProxyStrategy(
            id: existing?.id ?? newProxyID(), name: trimmedName, type: type,
            members: members, uses: "",
            sourceSubscriptions: autoAllSubscriptions ? [] : selectedSubscriptions,
            nodeSources: autoAllNodes ? [] : selectedNodes,
            regions: regions, customFilter: "",
            dialerProxy: dialerProxy.trimmingCharacters(in: .whitespaces),
            includeProxy: includeProxy,
            autoAllSubscriptions: autoAllSubscriptions, autoAllNodes: autoAllNodes
        )
        if let existing {
            if let index = draft.strategies.firstIndex(where: { $0.id == existing.id }) {
                draft.strategies[index] = strategy
            }
            if existing.name != trimmedName {
                proxyRepointPolicy(from: existing.name, to: trimmedName, draft: &draft)
            }
        } else {
            draft.strategies.append(strategy)
        }
        dismiss()
    }
}

private func proxyDialerSuggestions(draft: ConfigData, excluding name: String) -> [String] {
    var names = ["Proxy"]
    names.append(contentsOf: draft.strategies.map { $0.name }.filter { $0 != name })
    names.append(contentsOf: draft.nodeLinks.compactMap { node in
        let parsed = parseProxyNodeLink(node.url, fallbackName: node.name)
        return parsed.ok ? parsed.name : nil
    })
    return proxyUniqueValues(names)
}

// MARK: - Provider

struct ProxyProviderSheet: View {
    @Binding var draft: ConfigData
    let existing: ProxyProvider?
    /// Shadowrocket providers have no behavior field — the
    /// generator only reads url + policy for .conf output.
    let shadowrocket: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var policy: String
    @State private var behavior: String
    @State private var url: String
    @State private var error = ""

    init(draft: Binding<ConfigData>, existing: ProxyProvider?, shadowrocket: Bool = false) {
        _draft = draft
        self.existing = existing
        self.shadowrocket = shadowrocket
        _name = State(initialValue: existing?.name ?? "")
        _policy = State(initialValue: existing?.policy ?? "Proxy")
        _behavior = State(initialValue: existing?.behavior ?? "classical")
        _url = State(initialValue: existing?.url ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("规则名称", text: $name)
                Picker("命中后使用", selection: $policy) {
                    ForEach(proxyAvailablePolicies(draft), id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                if !shadowrocket {
                    Picker("行为 behavior", selection: $behavior) {
                        Text("classical").tag("classical")
                        Text("domain").tag("domain")
                        Text("ipcidr").tag("ipcidr")
                    }
                }
                TextField(shadowrocket ? "Shadowrocket .list URL" : "Clash / Mihomo YAML URL", text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(existing == nil ? "添加在线规则集" : "编辑规则集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else {
            error = "名称和 URL 不能为空。"
            return
        }
        if draft.providers.contains(where: { $0.name == trimmedName && $0.id != existing?.id }) {
            error = "规则名称已存在，请换一个名称。"
            return
        }
        if let existing {
            if let index = draft.providers.firstIndex(where: { $0.id == existing.id }) {
                draft.providers[index].name = trimmedName
                draft.providers[index].url = trimmedURL
                draft.providers[index].behavior = behavior
                draft.providers[index].policy = policy
            }
        } else {
            let id = newProxyID()
            draft.providers.append(ProxyProvider(id: id, key: "ruleset-" + id, name: trimmedName, url: trimmedURL, behavior: behavior, policy: policy))
        }
        dismiss()
    }
}

// MARK: - Repo search (inside the providers section)

struct ProxyRepoSearchView: View {
    @Binding var config: ConfigData
    /// Which software's catalog entries to add: Shadowrocket
    /// gets rule/Shadowrocket/<slug>/<slug>.list, Clash gets
    /// rule/Clash/<slug>/<slug>.yaml — never mixed.
    let shadowrocket: Bool
    @State private var query = ""
    @State private var addPolicy = "Proxy"

    private var results: [RepoRule] {
        proxyRepoSearchResults(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("搜索 ios_rule_script")
                .font(.subheadline)
            Text(shadowrocket ? "按服务名、中文别名或分类查找 Shadowrocket .list 规则集。" : "按服务名、中文别名或分类查找 Clash YAML 规则集。")
                .font(.caption)
                .foregroundColor(.gray)
            TextField("例如 OpenAI、Netflix、贴吧、广告", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Picker("加入时使用的策略", selection: $addPolicy) {
                ForEach(proxyAvailablePolicies(config), id: \.self) { p in
                    Text(p).tag(p)
                }
            }
            .pickerStyle(.menu)
            if results.isEmpty {
                Text("没有匹配的常用规则。可到 blackmatrix7/ios_rule_script 确认目录名，再手动粘贴规则。")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(results, id: \.slug) { item in
                    let added = config.providers.contains { $0.name == item.slug || $0.url == proxyRepoRuleURL(item.slug, shadowrocket: shadowrocket) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.slug).font(.subheadline)
                            Text(item.category + (item.aliases.isEmpty ? "" : " · " + item.aliases))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button(added ? "已加入" : "使用") {
                            guard !added else { return }
                            config.providers.append(ProxyProvider(
                                id: newProxyID(), key: "", name: item.slug,
                                url: proxyRepoRuleURL(item.slug, shadowrocket: shadowrocket),
                                behavior: "classical", policy: addPolicy
                            ))
                        }
                        .buttonStyle(.bordered)
                        .disabled(added)
                    }
                }
            }
        }
    }
}

// MARK: - Single rule

struct ProxyRuleSheet: View {
    @Binding var draft: ConfigData
    let existing: ProxyRule?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var value: String
    @State private var policy: String
    @State private var noResolve: Bool
    @State private var error = ""

    init(draft: Binding<ConfigData>, existing: ProxyRule?) {
        _draft = draft
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? "DOMAIN-SUFFIX")
        _value = State(initialValue: existing?.value ?? "")
        _policy = State(initialValue: existing?.policy ?? "Proxy")
        _noResolve = State(initialValue: existing?.noResolve ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("规则类型", selection: $kind) {
                    ForEach(proxyRuleKinds, id: \.self) { k in
                        Text(k).tag(k)
                    }
                }
                TextField("匹配内容", text: $value)
                    .disabled(kind == "MATCH")
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Picker("策略", selection: $policy) {
                    ForEach(proxyAvailablePolicies(draft), id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                Toggle("no-resolve（仅 IP 类规则使用）", isOn: $noResolve)
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(existing == nil ? "添加规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        if kind != "MATCH" && value.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "匹配内容不能为空。"
            return
        }
        if let existing {
            if let index = draft.rules.firstIndex(where: { $0.id == existing.id }) {
                draft.rules[index].kind = kind
                draft.rules[index].value = kind == "MATCH" ? "" : value.trimmingCharacters(in: .whitespaces)
                draft.rules[index].policy = policy
                draft.rules[index].noResolve = noResolve
            }
        } else {
            draft.rules.append(ProxyRule(
                id: newProxyID(), name: "手动规则", kind: kind,
                value: kind == "MATCH" ? "" : value.trimmingCharacters(in: .whitespaces),
                policy: policy, noResolve: noResolve
            ))
        }
        dismiss()
    }
}

// MARK: - Batch paste

struct ProxyBatchSheet: View {
    @Binding var draft: ConfigData
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var defaultPolicy = "Proxy"
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("缺省策略", selection: $defaultPolicy) {
                    ForEach(proxyAvailablePolicies(draft), id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("支持 Quantumult X、Shadowrocket 与 Clash 写法；没有行内策略时使用上面的缺省策略。")
                    .font(.caption)
                    .foregroundColor(.gray)
                if !error.isEmpty {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle("批量添加分流规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("识别并加入", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            let parsed = try proxyParseRuleBatch(text, defaultPolicy: defaultPolicy, batchName: "")
            draft.rules.append(contentsOf: parsed)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
