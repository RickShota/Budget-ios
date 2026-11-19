import SwiftUI

// MARK: - 收支明细

struct RecordsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var filter: RecordFilter = .all
    @State private var collapsedMonths: Set<String> = []
    @State private var editingRecord: ExpenseRecord?
    @State private var pendingDelete: ExpenseRecord?

    enum RecordFilter: String, CaseIterable, Identifiable {
        case all, expense, income

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "全部"
            case .expense: "支出"
            case .income: "收入"
            }
        }
    }

    private struct MonthGroup: Identifiable {
        let month: String
        var items: [ExpenseRecord]
        var id: String { month }
    }

    var body: some View {
        List {
            Section {
                Picker("筛选", selection: $filter) {
                    ForEach(RecordFilter.allCases) { item in
                        Text("\(item.title) \(count(for: item))").tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "tray")
                    } description: {
                        Text("去「记一笔」添加第一笔吧")
                    }
                    .clearListRowBackground()
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        if !collapsedMonths.contains(group.month) {
                            ForEach(group.items) { record in
                                Button {
                                    editingRecord = record
                                } label: {
                                    RecordRow(record: record)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = record
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        editingRecord = record
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        pendingDelete = record
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        monthHeader(group)
                    }
                }
            }

            Section {
                Button {
                    dismiss()
                } label: {
                    Label("记一笔", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .clearListRowBackground()
            }
        }
        .appListStyle()
        .navigationTitle("收支明细")
        .sheet(item: $editingRecord) { record in
            RecordEditorSheet(record: record)
        }
        .alert("删除记录", isPresented: deleteAlertBinding, presenting: pendingDelete) { record in
            Button("删除", role: .destructive) {
                store.deleteExpense(id: record.id)
                store.showToast("已删除")
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { record in
            Text("删除这条\(record.type == .income ? "收入" : "支出")记录（\(record.cat) \(Money.string(record.amount))）？")
        }
    }

    // MARK: - 数据

    private var sortedExpenses: [ExpenseRecord] {
        store.db.expenses.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id > b.id
        }
    }

    private var filtered: [ExpenseRecord] {
        switch filter {
        case .all: sortedExpenses
        case .expense: sortedExpenses.filter { $0.type != .income }
        case .income: sortedExpenses.filter { $0.type == .income }
        }
    }

    private var groups: [MonthGroup] {
        var result: [MonthGroup] = []
        for record in filtered {
            let month = String(record.date.prefix(7))
            if result.last?.month == month {
                result[result.count - 1].items.append(record)
            } else {
                result.append(MonthGroup(month: month, items: [record]))
            }
        }
        return result
    }

    private func count(for filter: RecordFilter) -> Int {
        switch filter {
        case .all: store.db.expenses.count
        case .expense: store.db.expenses.filter { $0.type != .income }.count
        case .income: store.db.expenses.filter { $0.type == .income }.count
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    // MARK: - 月份分组头

    private func monthHeader(_ group: MonthGroup) -> some View {
        let income = group.items.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = group.items.filter { $0.type != .income }.reduce(0) { $0 + $1.amount }
        let parts = group.month.split(separator: "-")
        let title: String = {
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
                return group.month
            }
            return "\(year)年\(month)月"
        }()
        let isCollapsed = collapsedMonths.contains(group.month)

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isCollapsed {
                    collapsedMonths.remove(group.month)
                } else {
                    collapsedMonths.insert(group.month)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("收 \(Money.string(income)) · 支 \(Money.string(expense))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}

// MARK: - 记录行

struct RecordRow: View {
    let record: ExpenseRecord

    var body: some View {
        let isIncome = record.type == .income
        HStack(spacing: 12) {
            Image(systemName: Categories.symbol(for: record.cat, type: record.type))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isIncome ? Color.green : Color.secondary)
                .frame(width: 34, height: 34)
                .background(
                    (isIncome ? Color.green : Color.secondary).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.cat)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !record.note.isEmpty {
                        Text("· \(record.note)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(record.date + (record.periodId == nil ? " · 未计入账期" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text((isIncome ? "+" : "-") + Money.string(record.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isIncome ? Color.green : Color.primary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - 编辑单条记录

struct RecordEditorSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let record: ExpenseRecord

    @State private var type: EntryType
    @State private var amountText: String
    @State private var cat: String
    @State private var note: String
    @State private var date: Date
    @State private var confirmDelete = false
    @State private var formAlert: String?

    init(record: ExpenseRecord) {
        self.record = record
        _type = State(initialValue: record.type)
        _amountText = State(initialValue: Self.amountString(record.amount))
        _cat = State(initialValue: record.cat)
        _note = State(initialValue: record.note)
        _date = State(initialValue: DateX.parse(record.date) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $type) {
                        Text("− 支出").tag(EntryType.expense)
                        Text("＋ 收入").tag(EntryType.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section("金额") {
                    TextField("0.00", text: $amountText)
                        .decimalPadKeyboard()
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }

                Section("分类") {
                    Picker("分类", selection: $cat) {
                        ForEach(Categories.list(for: type)) { category in
                            Label(category.key, systemImage: category.symbol).tag(category.key)
                        }
                    }
                }

                Section {
                    TextField("备注（可选）", text: $note)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(periodHint)
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除这条记录", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .dismissKeyboardOnScroll()
            .navigationTitle("编辑记录")
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
            .onChange(of: type) { _, newType in
                let list = Categories.list(for: newType)
                if !list.contains(where: { $0.key == cat }) {
                    cat = list.first?.key ?? "其他"
                }
            }
            .alert("删除记录", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    store.deleteExpense(id: record.id)
                    dismiss()
                    store.showToast("已删除")
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除这条记录（\(record.cat) \(Money.string(record.amount))）？")
            }
        }
        .largeSheet()
        .alertMessage($formAlert)
    }

    private var periodHint: String {
        if let period = store.findPeriod(date: DateX.iso(date)) {
            return "将计入「\(period.name)」"
        }
        return "注意：该日期不在任何账期内，将不计入额度"
    }

    private static func amountString(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private func save() {
        let cleaned = amountText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmed
        guard let amount = Double(cleaned), amount > 0 else {
            formAlert = "请输入有效金额"
            return
        }
        store.updateExpense(
            id: record.id,
            date: DateX.iso(date),
            amount: amount,
            type: type,
            cat: cat,
            note: note.trimmed
        )
        dismiss()
        store.showToast("已保存修改")
    }
}
