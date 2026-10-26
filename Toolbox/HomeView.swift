import SwiftUI
import SwiftData

/// 明细 tab: yellow header (month + monthly totals) over a white
/// date-grouped record list. No navigation chrome: the header itself
/// is the top of the screen and its yellow background extends into
/// the top safe area.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerRecord.date, order: .reverse) private var allRecords: [LedgerRecord]

    @State private var selectedMonth = startOfMonth(Date())
    @State private var editingRecord: LedgerRecord?

    private var monthRecords: [LedgerRecord] {
        allRecords.filter { isSameMonth($0.date, selectedMonth) }
    }

    private var incomeTotal: Double {
        monthRecords.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var expenseTotal: Double {
        monthRecords.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var days: [Date] {
        let grouped = Dictionary(grouping: monthRecords) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >)
    }

    private func records(on day: Date) -> [LedgerRecord] {
        monthRecords.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func daySummary(on day: Date) -> String {
        let dayRecords = records(on: day)
        let income = dayRecords.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
        let expense = dayRecords.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
        if income > 0 && expense > 0 {
            return "收入 \(formatMoney(income)) · 支出 \(formatMoney(expense))"
        } else if income > 0 {
            return "收入 \(formatMoney(income))"
        } else {
            return "支出 \(formatMoney(expense))"
        }
    }

    private func delete(_ offsets: IndexSet, on day: Date) {
        let dayRecords = records(on: day)
        for index in offsets {
            context.delete(dayRecords[index])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeHeaderView(
                month: selectedMonth,
                income: incomeTotal,
                expense: expenseTotal,
                onPrev: { selectedMonth = startOfMonth(shiftMonth(selectedMonth, by: -1)) },
                onNext: { selectedMonth = startOfMonth(shiftMonth(selectedMonth, by: 1)) }
            )
            if monthRecords.isEmpty {
                EmptyStateView(text: "暂无数据")
                    .frame(maxHeight: .infinity)
                    .background(Color.white)
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        Section(header: DaySectionHeader(day: day, summary: daySummary(on: day))) {
                            ForEach(records(on: day)) { record in
                                Button { editingRecord = record } label: {
                                    RecordRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { delete($0, on: day) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 20)
                }
            }
        }
        .background(Color.white)
        .fullScreenCover(item: $editingRecord) { record in
            RecordFormView(record: record)
        }
    }
}

private struct HomeHeaderView: View {
    let month: Date
    let income: Double
    let expense: Double
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(monthTitle(month))
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
            }
            HStack(spacing: 24) {
                TotalBlock(title: "本月收入", value: formatMoney(income))
                TotalBlock(title: "本月支出", value: formatMoney(expense))
            }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(AppTheme.yellow.ignoresSafeArea(edges: .top))
    }
}

private struct TotalBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

private struct DaySectionHeader: View {
    let day: Date
    let summary: String

    var body: some View {
        HStack {
            Text(dayTitle(day))
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

private struct RecordRow: View {
    let record: LedgerRecord

    var body: some View {
        let iconName: String = AppCategories.icon(for: record.category)
        let amountText: String = formatSignedMoney(record)
        let amountColor: Color = record.isIncome ? .green : .primary
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
                .background(AppTheme.iconBackground)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(record.category)
                    .font(.subheadline)
                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(amountText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(amountColor)
        }
        .padding(.vertical, 4)
    }
}
