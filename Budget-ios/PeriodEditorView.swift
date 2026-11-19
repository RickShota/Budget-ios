import SwiftUI

// MARK: - 新建 / 编辑账期

struct PeriodEditorSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: BudgetPeriod?

    @State private var name: String
    @State private var start: Date
    @State private var end: Date
    @State private var incomes: [LedgerItem]
    @State private var fixed: [LedgerItem]
    @State private var confirmDelete = false
    @State private var formAlert: String?
    @State private var templateMessage: String?

    init(period: BudgetPeriod?) {
        existing = period
        let now = Date()
        _name = State(initialValue: period?.name ?? "")
        _start = State(initialValue: period.flatMap { DateX.parse($0.start) } ?? now)
        _end = State(initialValue: period.flatMap { DateX.parse($0.end) } ?? now)
        _incomes = State(initialValue: period?.incomes ?? [LedgerItem()])
        _fixed = State(initialValue: period?.fixed ?? [LedgerItem()])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账期名称", text: $name, prompt: Text("账期名称（如：10月24日~11月23日）"))
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                    DatePicker("结束日期", selection: $end, displayedComponents: .date)
                }

                Section {
                    ForEach($incomes) { $item in
                        LabeledAmountRow(
                            label: $item.label,
                            amount: $item.amount,
                            onDelete: { incomes.removeAll { $0.id == item.id } }
                        )
                    }
                    Button {
                        incomes.append(LedgerItem())
                    } label: {
                        Label("添加收入", systemImage: "plus.circle")
                    }
                } header: {
                    Text("收入项")
                } footer: {
                    Text("可多笔，例如：工资、补贴。")
                }

                Section {
                    ForEach($fixed) { $item in
                        LabeledAmountRow(
                            label: $item.label,
                            amount: $item.amount,
                            onDelete: { fixed.removeAll { $0.id == item.id } }
                        )
                    }
                    Button {
                        fixed.append(LedgerItem())
                    } label: {
                        Label("添加固定支出", systemImage: "plus.circle")
                    }
                } header: {
                    Text("固定支出项")
                } footer: {
                    Text("可多笔，例如：月供、房租伙食。")
                }

                Section {
                    Button(action: applyTemplate) {
                        Label("按日期范围从模板带入收支", systemImage: "arrow.triangle.2.circlepath")
                    }
                } footer: {
                    if let templateMessage {
                        Text(templateMessage)
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("删除该账期", systemImage: "trash")
                        }
                    }
                }
            }
            .appFormStyle()
            .dismissKeyboardOnScroll()
            .navigationTitle(existing == nil ? "新建账期" : "编辑账期")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .alert("删除该账期", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    if let existing {
                        store.deletePeriod(id: existing.id)
                    }
                    dismiss()
                    store.showToast("已删除")
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除该账期？其下的支出记录会保留但不再计入额度。")
            }
        }
        .largeSheet()
        .macSheetSize()
        .alertMessage($formAlert)
    }

    private func applyTemplate() {
        let startString = DateX.iso(start)
        let endString = DateX.iso(end)
        var added = 0

        for item in store.rulesForPeriod(start: startString, end: endString, type: .income)
        where !incomes.contains(where: { $0.label == item.label }) {
            incomes.append(LedgerItem(label: item.label, amount: item.amount))
            added += 1
        }
        for item in store.rulesForPeriod(start: startString, end: endString, type: .expense)
        where !fixed.contains(where: { $0.label == item.label }) {
            fixed.append(LedgerItem(label: item.label, amount: item.amount))
            added += 1
        }

        templateMessage = added > 0 ? "已带入 \(added) 条模板收支" : "区间内没有匹配的模板收支"
    }

    private func save() {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else {
            formAlert = "请填写名称和日期"
            return
        }
        let startString = DateX.iso(start)
        let endString = DateX.iso(end)
        guard endString >= startString else {
            formAlert = "结束日期不能早于开始日期"
            return
        }

        let cleanedIncomes = incomes
            .filter { !$0.label.trimmed.isEmpty && $0.amount > 0 }
            .map { LedgerItem(label: $0.label.trimmed, amount: $0.amount) }
        let cleanedFixed = fixed
            .filter { !$0.label.trimmed.isEmpty && $0.amount > 0 }
            .map { LedgerItem(label: $0.label.trimmed, amount: $0.amount) }

        let period = BudgetPeriod(
            id: existing?.id ?? UUID().uuidString,
            name: trimmedName,
            start: startString,
            end: endString,
            incomes: cleanedIncomes,
            fixed: cleanedFixed
        )
        store.upsertPeriod(period, isNew: existing == nil)
        dismiss()
        store.showToast("账期已保存")
    }
}

// MARK: - 名称 + 金额行

struct LabeledAmountRow: View {
    @Binding var label: String
    @Binding var amount: Double
    var onDelete: () -> Void

    @State private var amountText: String

    init(label: Binding<String>, amount: Binding<Double>, onDelete: @escaping () -> Void) {
        _label = label
        _amount = amount
        self.onDelete = onDelete
        let value = amount.wrappedValue
        _amountText = State(initialValue: Self.text(for: value))
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("名称", text: $label)
            TextField("金额", text: $amountText)
                .decimalPadKeyboard()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 96)
                .onChange(of: amountText) { _, newValue in
                    let cleaned = newValue
                        .replacingOccurrences(of: "，", with: ".")
                        .replacingOccurrences(of: ",", with: ".")
                        .trimmed
                    amount = Double(cleaned) ?? 0
                }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除这一行")
        }
    }

    private static func text(for value: Double) -> String {
        guard value != 0 else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(value)
    }
}

// MARK: - 按模板自动生成账期

struct GeneratePeriodsSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var anchorsText = ""
    @State private var count = 6
    @State private var tag = ""
    @State private var didInit = false
    @State private var formAlert: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("第一个账期开始日期", selection: $start, displayedComponents: .date)
                    TextField("周期锚点日", text: $anchorsText, prompt: Text("如：11,24"))
                        .numbersKeyboard()
                    Stepper("生成期数：\(count)", value: $count, in: 1...24)
                    TextField("名称备注（可选）", text: $tag, prompt: Text("如：试用期"))
                } footer: {
                    Text("以固定收支模板为准，自动生成若干个账期，并把日期落在区间内的收支自动填入。已存在的起始日会自动跳过。")
                }

                Section {
                    Text(incomeDaysHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.db.rules.isEmpty {
                    Section {
                        Label("还没有模板，生成后只有日期框架，可先去「设置」添加。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .appFormStyle()
            .navigationTitle("按模板生成账期")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成") { generate() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear(perform: primeDefaults)
        }
        .adaptiveSheet()
        .macSheetSize()
        .alertMessage($formAlert)
    }

    private var incomeDaysHint: String {
        let days = Array(Set(store.db.rules.filter { $0.type == .income }.flatMap(\.days))).sorted()
        let daysText = days.isEmpty
            ? "（模板里还没有收入）"
            : days.map { String($0) }.joined(separator: "、") + " 号"
        return "你的收入日期是 \(daysText)。若工资分两次发，填「11,24」会切出「24号~次月10号」「11号~23号」两期，每期刚好对应一次发薪。"
    }

    private func primeDefaults() {
        guard !didInit else { return }
        didInit = true
        if let last = store.sortedPeriods.last {
            start = DateX.parse(DateX.addDays(last.end, 1)) ?? Date()
        } else {
            start = Date()
        }
        anchorsText = store.defaultAnchors()
    }

    private func generate() {
        let anchors = anchorsText
            .split(whereSeparator: { ",，、 \n".contains($0) })
            .compactMap { Int($0) }
            .filter { (1...31).contains($0) }
        guard !anchors.isEmpty else {
            formAlert = "请填写周期锚点日，如 11,24"
            return
        }
        let created = store.generatePeriods(
            start: DateX.iso(start),
            anchors: anchors,
            count: count,
            tag: tag.trimmed
        )
        dismiss()
        store.selectedTab = .periods
        store.showToast(created > 0 ? "已生成 \(created) 个账期" : "没有新增（起始日都已存在）")
    }
}
