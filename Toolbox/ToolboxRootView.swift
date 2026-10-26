import SwiftUI

/// The three functions in one app. Each keeps its own UI intact:
/// 记账 keeps its 明细/图表 shell, 卡密 keeps its list, 网页 keeps
/// its import list + viewer. Switching happens only here: the
/// floating button opens the switch page. There is no system tab
/// bar, so no function ever shows two stacked bars.
enum ToolboxTab: String, CaseIterable {
    case ledger = "记账"
    case cardcodes = "卡密"
    case web = "网页"
}

struct ToolboxRootView: View {
    @State private var tab: ToolboxTab = .ledger
    @State private var showingSwitcher = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch tab {
                case .ledger:
                    LedgerRootView()
                case .cardcodes:
                    CardCodesRootView()
                case .web:
                    WebRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                showingSwitcher = true
            } label: {
                Image(systemName: "rectangle.3.offgrid.fill")
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .liquidGlassCircle()
            }
            .padding(.trailing, 20)
            // Clears the ledger tab's own bottom bar; on the other
            // tabs it simply floats a little higher.
            .padding(.bottom, 110)
        }
        .sheet(isPresented: $showingSwitcher) {
            SwitcherView(current: tab) { selected in
                tab = selected
                showingSwitcher = false
            }
            .presentationDetents([.medium])
        }
    }
}

/// The switch page: one card per function, current one marked.
/// Plain VStack rows (not a List): the whole row is the button,
/// so tapping anywhere on a row switches — no dead zones.
struct SwitcherView: View {
    let current: ToolboxTab
    let onSelect: (ToolboxTab) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
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
