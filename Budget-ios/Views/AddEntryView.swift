import SwiftUI

struct AddEntryView: View {
    @Environment(BudgetStore.self) private var store

    @State private var type: EntryType = .expense
    @State private var selectedExpenseCat = "餐饮"
    @State private var selectedIncomeCat = "工资"
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @FocusState private var amountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 32

    private var selectedCat: String {
        type == .income ? selectedIncomeCat : selectedExpenseCat
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let period = store.currentPeriod() {
                    periodStrip(period)
                }
                entryCard
                recordsLink
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .readableWidth(560)
        }
        .background(Color.appGroupedBackground)
        .dismissKeyboardOnScroll()
        .navigationTitle("记一笔")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button("保存", action: save)
            .fontWeight(.semibold)
            .keyboardShortcut(.defaultAction)
    }

    // MARK: - 当前账期条

    private func periodStrip(_ period: BudgetPeriod) -> some View {
        let remain = store.periodRemain(period)
        return Card {
            HStack {
                Text(period.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("额度 \(Money.string(store.periodBudget(period)))")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("剩余 \(Money.string(remain))")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(remain < 0 ? Color.red : Color.primary)
                Spacer()
                Text("\(period.end) 结束")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 记账表单

    private var entryCard: some View {
        Card {
            Picker("类型", selection: $type) {
                Text("− 支出").tag(EntryType.expense)
                Text("＋ 收入").tag(EntryType.income)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("金额")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .decimalPadKeyboard()
                    .focused($amountFocused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: amountFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.appGroupedBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("分类")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(Categories.list(for: type)) { category in
                        categoryChip(category)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("可选，比如：午饭", text: $note)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Color.appGroupedBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }

            HStack {
                Label("日期", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }

            Text(hintText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func categoryChip(_ category: LedgerCategory) -> some View {
        let selected = category.key == selectedCat
        return Button {
            if type == .income {
                selectedIncomeCat = category.key
            } else {
                selectedExpenseCat = category.key
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.symbol)
                    .font(.caption)
                Text(category.key)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? Color.accentColor : Color.appFill.opacity(0.9),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var recordsLink: some View {
        NavigationLink {
            RecordsView()
        } label: {
            Label("查看全部收支明细", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var hintText: String {
        if let period = store.findPeriod(date: DateX.iso(date)) {
            return "保存后自动计入「\(period.name)」" + (type == .income ? "，并提升可支配额度" : "")
        }
        return "注意：该日期不在任何账期内，将不计入额度"
    }

    // MARK: - 保存

    private func save() {
        let cleaned = amountText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmed
        guard let amount = Double(cleaned), amount > 0 else {
            store.showToast("请输入有效金额")
            return
        }

        let dateString = DateX.iso(date)
        let period = store.findPeriod(date: dateString)
        store.addExpense(
            date: dateString,
            amount: amount,
            type: type,
            cat: selectedCat,
            note: note.trimmed
        )

        let unit = type == .income ? "入账" : "支出"
        if let period {
            let remain = store.periodRemain(period)
            let budget = store.periodBudget(period)
            if remain < 0 {
                store.showToast("已记录\(unit)。⚠️ 本期超支 \(Money.string(-remain))！")
            } else if budget > 0, remain / budget < 0.2 {
                store.showToast("已记录\(unit)。剩余仅 \(Money.string(remain))，注意控制")
            } else {
                store.showToast("已记录\(unit)，本期剩余 \(Money.string(remain))")
            }
        } else {
            store.showToast("已记录\(unit)（未计入任何账期）")
        }

        amountText = ""
        note = ""
        amountFocused = false
    }
}
