import SwiftUI
import SwiftData

private enum ChartPeriod: String, CaseIterable {
    case week = "周"
    case month = "月"
    case year = "年"
}

private struct StripItem {
    let date: Date
    let title: String
    let subtitle: String
}

/// 图表 tab: yellow header (支出/收入 toggle, 周/月/年 segment,
/// period total + daily average), a horizontal date strip, and a
/// category ranking list. No navigation chrome.
struct StatisticsView: View {
    @Query(sort: \LedgerRecord.date, order: .reverse) private var allRecords: [LedgerRecord]

    @State private var isIncome = false
    @State private var period: ChartPeriod = .month
    @State private var anchor = Date()

    private var range: (start: Date, end: Date) {
        let calendar = Calendar.current
        switch period {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: anchor)
            return (interval?.start ?? anchor, interval?.end ?? anchor)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: anchor)
            return (interval?.start ?? anchor, interval?.end ?? anchor)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: anchor)
            return (interval?.start ?? anchor, interval?.end ?? anchor)
        }
    }

    private var periodRecords: [LedgerRecord] {
        allRecords.filter {
            $0.isIncome == isIncome && $0.date >= range.start && $0.date < range.end
        }
    }

    private var total: Double {
        periodRecords.reduce(0) { $0 + $1.amount }
    }

    private var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: range.start, to: range.end).day ?? 1
        return max(days, 1)
    }

    private var average: Double {
        total / Double(dayCount)
    }

    private var totalLabel: String {
        let typeText = isIncome ? "收入" : "支出"
        switch period {
        case .week: return "本周总\(typeText)"
        case .month: return "本月总\(typeText)"
        case .year: return "本年总\(typeText)"
        }
    }

    private var periodTitle: String {
        switch period {
        case .week:
            let endDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(shortDayTitle(range.start)) - \(shortDayTitle(endDay))"
        case .month:
            return monthTitle(anchor)
        case .year:
            let year = Calendar.current.component(.year, from: anchor)
            return "\(year)年"
        }
    }

    private var stripItems: [StripItem] {
        let calendar = Calendar.current
        switch period {
        case .week:
            return (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: range.start) ?? range.start
                return StripItem(date: day, title: weekdayTitle(day), subtitle: dayNumber(day))
            }
        case .month:
            let year = calendar.component(.year, from: anchor)
            return (1...12).map { month in
                let day = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? anchor
                return StripItem(date: day, title: "\(month)月", subtitle: "")
            }
        case .year:
            let year = calendar.component(.year, from: anchor)
            return (year - 2...year + 2).map { itemYear in
                let day = calendar.date(from: DateComponents(year: itemYear, month: 1, day: 1)) ?? anchor
                return StripItem(date: day, title: "\(itemYear)年", subtitle: "")
            }
        }
    }

    private func weekdayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EE"
        return formatter.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return "\(day)"
    }

    private func isStripSelected(_ item: StripItem) -> Bool {
        switch period {
        case .week:
            return Calendar.current.isDate(item.date, inSameDayAs: anchor)
        case .month:
            return isSameMonth(item.date, anchor)
        case .year:
            let itemYear = Calendar.current.component(.year, from: item.date)
            let anchorYear = Calendar.current.component(.year, from: anchor)
            return itemYear == anchorYear
        }
    }

    private func stepPeriod(by value: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch period {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        anchor = calendar.date(byAdding: component, value: value, to: anchor) ?? anchor
    }

    private var ranking: [(name: String, total: Double)] {
        let grouped = Dictionary(grouping: periodRecords, by: { $0.category })
        return grouped
            .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(
                isIncome: $isIncome,
                period: $period,
                totalLabel: totalLabel,
                totalText: formatMoney(total),
                averageText: "平均 \(formatMoney(average)) / 天"
            )
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { stepPeriod(by: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(periodTitle)
                            .font(.headline)
                        Spacer()
                        Button { stepPeriod(by: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(stripItems.indices, id: \.self) { index in
                                let item = stripItems[index]
                                StripCell(
                                    item: item,
                                    isSelected: isStripSelected(item)
                                ) {
                                    anchor = item.date
                                }
                            }
                        }
                    }
                    if ranking.isEmpty {
                        EmptyStateView(text: "暂无数据")
                    } else {
                        VStack(spacing: 16) {
                            ForEach(ranking.indices, id: \.self) { index in
                                RankingRow(name: ranking[index].name, total: ranking[index].total)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 20)
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}

private struct StatsHeaderView: View {
    @Binding var isIncome: Bool
    @Binding var period: ChartPeriod
    let totalLabel: String
    let totalText: String
    let averageText: String

    var body: some View {
        VStack(spacing: 14) {
            TypeToggle(isIncome: $isIncome)
            HStack(spacing: 8) {
                ForEach(ChartPeriod.allCases, id: \.self) { item in
                    PeriodSegmentButton(
                        title: item.rawValue,
                        isSelected: period == item
                    ) {
                        period = item
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(totalLabel)
                    .font(.subheadline)
                Text(totalText)
                    .font(.system(size: 28, weight: .bold))
                Text(averageText)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(AppTheme.yellow.ignoresSafeArea(edges: .top))
    }
}

private struct PeriodSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
        } else {
            Button(action: action) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(Color.black, lineWidth: 1))
            }
        }
    }
}

private struct StripCell: View {
    let item: StripItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let bgColor: Color = isSelected ? AppTheme.yellow : AppTheme.iconBackground
        Button(action: action) {
            VStack(spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                }
            }
            .foregroundColor(.black)
            .frame(minWidth: 44)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct RankingRow: View {
    let name: String
    let total: Double

    var body: some View {
        let iconName: String = AppCategories.icon(for: name)
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
                .background(AppTheme.iconBackground)
                .clipShape(Circle())
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(formatMoney(total))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}
