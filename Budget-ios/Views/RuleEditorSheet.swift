import SwiftUI

// MARK: - 新增 / 编辑固定收支模板

struct RuleEditorSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: FixedRule?

    @State private var type: EntryType
    @State private var label: String
    @State private var amountText: String
    @State private var daysText: String
    @State private var hasRange: Bool
    @State private var rangeStart: Date
    @State private var rangeEnd: Date
    @State private var confirmDelete = false
    @State private var formAlert: String?

    init(rule: FixedRule?) {
        existing = rule
        let now = Date()
        _type = State(initialValue: rule?.type ?? .income)
        _label = State(initialValue: rule?.label ?? "")
        _amountText = State(initialValue: Self.amountString(rule?.amount ?? 0, hasValue: rule != nil))
        _daysText = State(initialValue: rule?.days.map { String($0) }.joined(separator: ",") ?? "")
        _hasRange = State(initialValue: rule.map { !$0.rangeStart.isEmpty || !$0.rangeEnd.isEmpty } ?? false)
        _rangeStart = State(initialValue: rule.flatMap { DateX.parse($0.rangeStart) } ?? now)
        _rangeEnd = State(initialValue: rule.flatMap { DateX.parse($0.rangeEnd) } ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $type) {
                        Text("收入").tag(EntryType.income)
                        Text("固定支出").tag(EntryType.expense)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("名称", text: $label, prompt: Text("如：工资、月供、房租"))
                    TextField("金额", text: $amountText, prompt: Text("0.00"))
                        .decimalPadKeyboard()
                    TextField("每月日期", text: $daysText, prompt: Text("多个用逗号分隔，如 5,20"))
                        .numbersKeyboard()
                } footer: {
                    Text("工资分两次发就填 5,20；每月 24 号发一次就填 24。")
                }

                Section {
                    Toggle("设置生效范围", isOn: $hasRange)
                    if hasRange {
                        DatePicker("开始", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("结束", selection: $rangeEnd, displayedComponents: .date)
                    }
                } footer: {
                    Text("可选，留空表示一直有效。例如试用期工资只到 12 月 23 日：结束日期填 2026-12-23，之后的账期就不会再带入这条。")
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("删除该模板", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .appFormStyle()
            .dismissKeyboardOnScroll()
            .navigationTitle(existing == nil ? "新增固定收支模板" : "编辑模板")
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
            .alert("删除模板", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    if let existing {
                        store.deleteRule(id: existing.id)
                    }
                    dismiss()
                    store.showToast("已删除")
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除模板「\(existing?.label ?? "")」？已生成的账期不受影响。")
            }
        }
        .adaptiveSheet()
        .macSheetSize()
        .alertMessage($formAlert)
    }

    private static func amountString(_ value: Double, hasValue: Bool) -> String {
        guard hasValue else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    private func save() {
        let trimmedLabel = label.trimmed
        guard !trimmedLabel.isEmpty else {
            formAlert = "请填写名称"
            return
        }

        let cleanedAmount = amountText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmed
        guard let amount = Double(cleanedAmount), amount > 0 else {
            formAlert = "请填写有效金额"
            return
        }

        let days = Array(
            Set(
                daysText
                    .split(whereSeparator: { ",，、 \n".contains($0) })
                    .compactMap { Int($0) }
                    .filter { (1...31).contains($0) }
            )
        ).sorted()
        guard !days.isEmpty else {
            formAlert = "请填写每月日期，如 24 或 5,20"
            return
        }

        let startString = hasRange ? DateX.iso(rangeStart) : ""
        let endString = hasRange ? DateX.iso(rangeEnd) : ""
        if !startString.isEmpty, !endString.isEmpty, endString < startString {
            formAlert = "生效结束日期不能早于开始日期"
            return
        }

        let rule = FixedRule(
            id: existing?.id ?? UUID().uuidString,
            type: type,
            label: trimmedLabel,
            amount: amount,
            days: days,
            rangeStart: startString,
            rangeEnd: endString
        )
        store.upsertRule(rule, isNew: existing == nil)
        dismiss()
        store.showToast("模板已保存")
    }
}
