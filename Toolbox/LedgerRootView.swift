import SwiftUI

enum MainTab {
    case list
    case chart
}

/// Custom shell: content area + a custom bottom tab bar with a raised
/// yellow + button in the centre. No system tab component, no 发现/我的 tabs:
/// this app is bookkeeping only (明细 / 图表).
struct LedgerRootView: View {
    @State private var tab: MainTab = .list
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            contentView
            CustomTabBar(tab: $tab, onAdd: { showingAdd = true })
        }
        .background(Color.white)
        .fullScreenCover(isPresented: $showingAdd) {
            RecordFormView(record: nil)
        }
    }

    private var contentView: some View {
        Group {
            if tab == .list {
                HomeView()
            } else {
                StatisticsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty state shared by the list and chart screens: a document
/// SF Symbol above 暂无数据, centred by the caller.
struct EmptyStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text(text)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct CustomTabBar: View {
    @Binding var tab: MainTab
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TabBarButton(title: "明细", icon: "list.bullet", isSelected: tab == .list) {
                tab = .list
            }
            addButton
            TabBarButton(title: "图表", icon: "chart.bar.fill", isSelected: tab == .chart) {
                tab = .chart
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 60, height: 60)
                .background(AppTheme.yellow)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
        }
        .offset(y: -18)
    }
}

private struct TabBarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let labelColor: Color = isSelected ? .black : .gray
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(labelColor)
        }
    }
}
