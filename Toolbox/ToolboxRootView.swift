import SwiftUI

/// The five functions in one app. Each keeps its own UI intact:
/// 记账 keeps its 明细/图表 shell, 卡密 keeps its list, 网页 keeps
/// its import list + viewer, 代理规则 keeps its config list +
/// editor + output. Launch always shows the chooser page
/// (LauncherView): pick a function to open it directly, no
/// remembered tab. After that, switching happens here: the
/// floating button opens the switch page, which also has a
/// 启动页 row to come back. There is no system tab bar, so no
/// function ever shows two stacked bars.
enum ToolboxTab: String, CaseIterable {
    case ledger = "记账"
    case cardcodes = "卡密"
    case web = "网页"
    case download = "下载"
    case proxy = "代理规则"
}

struct ToolboxRootView: View {
    /// nil = launch chooser page, no function open yet.
    @State private var tab: ToolboxTab? = nil
    @State private var showingSwitcher = false
    @State private var floatPosition = CGSize.zero
    @State private var dragTranslation = CGSize.zero

    var body: some View {
        Group {
            if let selected = tab {
                featureView(selected)
            } else {
                LauncherView { selected in
                    tab = selected
                }
            }
        }
        .sheet(isPresented: $showingSwitcher) {
            SwitcherView(current: tab) { selected in
                tab = selected
                showingSwitcher = false
            }
            .presentationDetents([.medium])
        }
    }

    /// One selected function + the floating switch button. The
    /// launcher (no selection yet) has no floating button: it
    /// already is the selection page.
    private func featureView(_ selected: ToolboxTab) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch selected {
                case .ledger:
                    LedgerRootView()
                case .cardcodes:
                    CardCodesRootView()
                case .web:
                    WebRootView()
                case .download:
                    DownloadRootView()
                case .proxy:
                    ProxyRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Draggable switch button. NOT a Button: a Button's
            // tap gesture swallows the drag, so the button never
            // followed the finger. This is a plain view with a
            // DragGesture (minimumDistance 0, so it tracks from
            // touch-down): a small movement on release counts as
            // a tap and opens the switcher, a real drag moves it.
            // Clamped on release so it cannot be dragged off
            // screen.
            Image(systemName: "rectangle.3.offgrid.fill")
                .font(.title3)
                .frame(width: 56, height: 56)
                .liquidGlassCircle()
                .contentShape(Circle())
                .offset(CGSize(width: floatPosition.width + dragTranslation.width,
                               height: floatPosition.height + dragTranslation.height))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragTranslation = value.translation
                        }
                        .onEnded { value in
                            dragTranslation = .zero
                            if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                                showingSwitcher = true
                            } else {
                                floatPosition = CGSize(
                                    width: min(20, max(-300, floatPosition.width + value.translation.width)),
                                    height: min(20, max(-500, floatPosition.height + value.translation.height))
                                )
                            }
                        }
                )
                .padding(.trailing, 20)
            // Clears the ledger tab's own bottom bar; on the other
            // tabs it simply floats a little higher.
            .padding(.bottom, 110)
        }
    }
}

/// The switch page: one card per function, current one marked.
/// Plain VStack rows (not a List): the whole row is the button,
/// so tapping anywhere on a row switches — no dead zones.
struct SwitcherView: View {
    let current: ToolboxTab?
    let onSelect: (ToolboxTab?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    SwitcherRow(
                        icon: "square.grid.2x2.fill",
                        color: .orange,
                        title: "启动页",
                        subtitle: "回到项目选择页",
                        isCurrent: current == nil
                    ) {
                        onSelect(nil)
                    }
                    SwitcherRow(
                        icon: "list.bullet",
                        color: AppTheme.yellow,
                        title: "记账",
                        subtitle: "简记账 · 明细与图表",
                        isCurrent: current == .ledger
                    ) {
                        onSelect(.ledger)
                    }
                    SwitcherRow(
                        icon: "key.fill",
                        color: CardTheme.accent,
                        title: "卡密",
                        subtitle: "卡密管家 · 点按复制",
                        isCurrent: current == .cardcodes
                    ) {
                        onSelect(.cardcodes)
                    }
                    SwitcherRow(
                        icon: "doc.text",
                        color: .blue,
                        title: "网页",
                        subtitle: "本地网页 · 本地 HTML 查看",
                        isCurrent: current == .web
                    ) {
                        onSelect(.web)
                    }
                    SwitcherRow(
                        icon: "arrow.down.circle",
                        color: .purple,
                        title: "下载",
                        subtitle: "视频解析 · 7 个平台",
                        isCurrent: current == .download
                    ) {
                        onSelect(.download)
                    }
                    SwitcherRow(
                        icon: "globe",
                        color: .green,
                        title: "代理规则",
                        subtitle: "代理规则 · Clash / Shadowrocket 生成",
                        isCurrent: current == .proxy
                    ) {
                        onSelect(.proxy)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(CardTheme.background.ignoresSafeArea())
            .navigationTitle("切换功能")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SwitcherRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Liquid Glass circle for the floating switch button on iOS 26+,
/// plain black circle on older systems.
extension View {
    @ViewBuilder
    func liquidGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .foregroundColor(.primary)
                .glassEffect(.regular, in: Circle())
        } else {
            self
                .foregroundColor(.white)
                .background(Color.black.opacity(0.85))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
        }
    }
}

/// The launch page: pick a function and open it directly. Shown
/// on every launch (no remembered tab). Once a function is
/// picked, the floating button takes over switching, and the
/// switch sheet has a 启动页 row to come back here.
struct LauncherView: View {
    let onSelect: (ToolboxTab) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("工具箱")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("选一个项目，直接打开")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 4)
                SwitcherRow(
                    icon: "list.bullet",
                    color: AppTheme.yellow,
                    title: "记账",
                    subtitle: "简记账 · 明细与图表",
                    isCurrent: false
                ) {
                    onSelect(.ledger)
                }
                SwitcherRow(
                    icon: "key.fill",
                    color: CardTheme.accent,
                    title: "卡密",
                    subtitle: "卡密管家 · 点按复制",
                    isCurrent: false
                ) {
                    onSelect(.cardcodes)
                }
                SwitcherRow(
                    icon: "doc.text",
                    color: .blue,
                    title: "网页",
                    subtitle: "本地网页 · 本地 HTML 查看",
                    isCurrent: false
                ) {
                    onSelect(.web)
                }
                SwitcherRow(
                    icon: "arrow.down.circle",
                    color: .purple,
                    title: "下载",
                    subtitle: "视频解析 · 7 个平台",
                    isCurrent: false
                ) {
                    onSelect(.download)
                }
                SwitcherRow(
                    icon: "globe",
                    color: .green,
                    title: "代理规则",
                    subtitle: "代理规则 · Clash / Shadowrocket 生成",
                    isCurrent: false
                ) {
                    onSelect(.proxy)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(CardTheme.background.ignoresSafeArea())
    }
}
