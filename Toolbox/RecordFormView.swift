import SwiftUI
import SwiftData

/// Full-screen add/edit sheet. Yellow top area (type toggle, large
/// amount, date button), a scrollable 4-column category grid, a note
/// field, and a fixed custom numeric keypad at the bottom. The amount
/// never uses the system keyboard: the keypad builds the string itself.
struct RecordFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let record: LedgerRecord?

    @State private var isIncome: Bool
    @State private var amountText: String
    @State private var category: String
    @State private var date: Date
    @State private var note: String
    @State private var showDatePicker = false
    @State private var currency: String
    @State private var rateText: String
    @State private var rateMessage: String?

    init(record: LedgerRecord?) {
        self.record = record
        _isIncome = State(initialValue: record?.isIncome ?? false)
        _amountText = State(initialValue: RecordFormView.editingAmountText(for: record))
        _category = State(initialValue: record?.category ?? "餐饮")
        _date = State(initialValue: record?.date ?? Date())
        _note = State(initialValue: record?.note ?? "")
        _currency = State(initialValue: record?.currency ?? "CNY")
        _rateText = State(initialValue: RecordFormView.editingRateText(for: record))
    }

    private static func editingAmountText(for record: LedgerRecord?) -> String {
        guard let record else { return "" }
        var text = String(format: "%.2f", record.amount)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Editing a USD row reloads its locked rate; a new row (or a
    /// CNY row) starts from the last used rate, default 7.2.
    private static func editingRateText(for record: LedgerRecord?) -> String {
        if let rate = record?.exchangeRate, rate > 0 {
            return String(format: "%.4f", rate)
        }
        let saved = UserDefaults.standard.double(forKey: "ledgerUSDRate")
        return String(format: "%.2f", saved > 0 ? saved : 7.2)
    }

    private var categories: [String] {
        isIncome ? AppCategories.income : AppCategories.expense
    }

    private var amount: Double {
        Double(amountText) ?? 0
    }

    private var rate: Double {
        Double(rateText) ?? 0
    }

    /// Live RMB preview under the big amount when paying in USD.
    private var convertedText: String? {
        guard currency == "USD", amount > 0, rate > 0 else { return nil }
        return "≈ " + formatMoney(amount * rate)
    }

    private var displayAmount: String {
        amountText.isEmpty ? "0.00" : amountText
    }

    private var dateButtonTitle: String {
        isToday(date) ? "今天" : shortDayTitle(date)
    }

    var body: some View {
        VStack(spacing: 0) {
            EntryHeaderView(
                isIncome: $isIncome,
                displayAmount: displayAmount,
                currencySymbol: currency == "USD" ? "$" : "¥",
                convertedText: convertedText,
                date: $date,
                dateTitle: dateButtonTitle,
                showDatePicker: $showDatePicker,
                onCancel: { dismiss() }
            )
            ScrollView {
                VStack(spacing: 16) {
                    CurrencySectionView(
                        currency: $currency,
                        rateText: $rateText,
                        rateMessage: rateMessage,
                        onRefreshRate: refreshRate
                    )
                    CategoryGridView(categories: categories, selected: $category)
                    NoteRowView(note: $note)
                    if record != nil {
                        Button(role: .destructive) {
                            if let record {
                                context.delete(record)
                            }
                            dismiss()
                        } label: {
                            Text("删除这条记录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            KeypadView(
                onKey: { pressKey($0) },
                onDelete: { deleteKey() },
                onSave: { save() },
                saveDisabled: amount <= 0
            )
        }
        .background(Color.white)
        .onChange(of: isIncome) { _, newValue in
            category = (newValue ? AppCategories.income : AppCategories.expense).first ?? "其他"
        }
    }

    private func pressKey(_ key: String) {
        if key == "." {
            if amountText.isEmpty {
                amountText = "0."
            } else if !amountText.contains(".") {
                amountText += "."
            }
            return
        }
        if amountText.contains(".") {
            let decimals = amountText.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
            if decimals.count >= 2 { return }
            amountText += key
        } else {
            if amountText.count >= 9 { return }
            if amountText == "0" {
                amountText = key
            } else {
                amountText += key
            }
        }
    }

    private func deleteKey() {
        if !amountText.isEmpty {
            amountText.removeLast()
        }
    }

    private func save() {
        guard amount > 0 else { return }
        let savedRate: Double? = currency == "USD" && rate > 0 ? rate : nil
        if let savedRate {
            UserDefaults.standard.set(savedRate, forKey: "ledgerUSDRate")
        }
        if let record {
            record.amount = amount
            record.isIncome = isIncome
            record.category = category
            record.date = date
            record.note = note
            record.currency = currency
            record.exchangeRate = savedRate
        } else {
            context.insert(
                LedgerRecord(
                    amount: amount,
                    isIncome: isIncome,
                    category: category,
                    date: date,
                    note: note,
                    currency: currency,
                    exchangeRate: savedRate
                )
            )
        }
        dismiss()
    }

    /// Free no-key endpoint (open.er-api.com). On failure the
    /// current rate stays untouched and a note explains why.
    private func refreshRate() {
        rateMessage = "更新中…"
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let decoded = try? JSONDecoder().decode(ExchangeRateResponse.self, from: data),
                  let cny = decoded.rates["CNY"], cny > 0 else {
                DispatchQueue.main.async { rateMessage = "更新失败，沿用当前汇率" }
                return
            }
            DispatchQueue.main.async {
                rateText = String(format: "%.4f", cny)
                rateMessage = "已更新为实时汇率"
            }
        }.resume()
    }

    private struct ExchangeRateResponse: Decodable {
        let rates: [String: Double]
    }
}

/// 支出 / 收入 toggle with a black underline under the selected side.
/// Shared by the entry sheet and the chart header.
struct TypeToggle: View {
    @Binding var isIncome: Bool

    var body: some View {
        HStack(spacing: 24) {
            ToggleItem(title: "支出", isSelected: !isIncome) { isIncome = false }
            ToggleItem(title: "收入", isSelected: isIncome) { isIncome = true }
        }
    }
}

private struct ToggleItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let underlineColor: Color = isSelected ? .black : .clear
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Capsule()
                    .fill(underlineColor)
                    .frame(width: 28, height: 3)
            }
        }
    }
}

private struct EntryHeaderView: View {
    @Binding var isIncome: Bool
    let displayAmount: String
    let currencySymbol: String
    let convertedText: String?
    @Binding var date: Date
    let dateTitle: String
    @Binding var showDatePicker: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                TypeToggle(isIncome: $isIncome)
                Spacer()
                Button("取消", action: onCancel)
                    .foregroundColor(.black)
            }
            HStack {
                Text(currencySymbol + displayAmount)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Button { showDatePicker.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(dateTitle)
                    }
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            if let convertedText {
                Text(convertedText)
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showDatePicker {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(AppTheme.yellow.ignoresSafeArea(edges: .top))
    }
}

private struct CategoryGridView: View {
    let categories: [String]
    @Binding var selected: String

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ],
            spacing: 16
        ) {
            ForEach(categories, id: \.self) { item in
                CategoryCell(item: item, isSelected: selected == item) {
                    selected = item
                }
            }
        }
    }
}

/// One category button: circular light-gray icon background, yellow
/// circle when selected. Kept as its own view so the grid body stays
/// small for the compiler (see the Xcode 26.6 type-check timeout
/// on the old chained-modifier grid).
private struct CategoryCell: View {
    let item: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let iconName: String = AppCategories.icon(for: item)
        let bgColor: Color = isSelected ? AppTheme.yellow : AppTheme.iconBackground
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .background(bgColor)
                    .clipShape(Circle())
                Text(item)
                    .font(.caption)
                    .foregroundColor(.black)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct NoteRowView: View {
    @Binding var note: String

    var body: some View {
        HStack(spacing: 8) {
            Text("备注")
                .font(.subheadline)
                .foregroundColor(.black)
            TextField("点击填写备注", text: $note)
                .font(.subheadline)
        }
        .padding(12)
        .background(AppTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Fixed bottom keypad: four equal flexible columns (three digit
/// columns + the tall yellow 完成 column), sized proportionally so
/// it fits 375pt and 430pt screens alike and is never pushed
/// off-screen by a system keyboard (amount entry uses no system
/// keyboard at all).
private struct KeypadView: View {
    let onKey: (String) -> Void
    let onDelete: () -> Void
    let onSave: () -> Void
    let saveDisabled: Bool

    private let digitRows: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [".", "0", "delete"],
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ],
                    spacing: 0
                ) {
                    ForEach(digitRows.indices, id: \.self) { rowIndex in
                        ForEach(digitRows[rowIndex], id: \.self) { key in
                            DigitKeyView(key: key, onKey: onKey, onDelete: onDelete)
                        }
                    }
                }
                .frame(width: geometry.size.width * 0.75)
                Button(action: onSave) {
                    Text("完成")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(saveDisabled ? AppTheme.yellow.opacity(0.4) : AppTheme.yellow)
                .disabled(saveDisabled)
                .frame(width: geometry.size.width * 0.25)
            }
        }
        .frame(height: 212)
        .background(Color.white)
    }
}

private struct DigitKeyView: View {
    let key: String
    let onKey: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        if key == "delete" {
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.title3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 53)
                    .background(Color.white)
            }
        } else {
            Button { onKey(key) } label: {
                Text(key)
                    .font(.title3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 53)
                    .background(Color.white)
            }
        }
    }
}

/// Currency row on the entry sheet: a CNY/USD segmented picker.
/// USD rows show an editable rate (1 USD = x RMB) plus a live-rate
/// refresh button; the rate is locked into the record on save, so
/// later rate moves never rewrite history.
private struct CurrencySectionView: View {
    @Binding var currency: String
    @Binding var rateText: String
    let rateMessage: String?
    let onRefreshRate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Picker("货币", selection: $currency) {
                Text("人民币 ¥").tag("CNY")
                Text("美元 $").tag("USD")
            }
            .pickerStyle(.segmented)
            if currency == "USD" {
                HStack(spacing: 8) {
                    Text("汇率")
                        .font(.subheadline)
                        .foregroundColor(.black)
                    Text("1 美元 =")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    TextField("7.20", text: $rateText)
                        .font(.subheadline)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    Text("人民币")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Button("实时汇率", action: onRefreshRate)
                        .font(.subheadline)
                }
                if let rateMessage {
                    Text(rateMessage)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(AppTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
