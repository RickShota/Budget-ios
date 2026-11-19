import SwiftUI

// MARK: - 账期列表

struct PeriodsView: View {
    @Environment(BudgetStore.self) private var store

    @State private var editingPeriod: BudgetPeriod?
    @State private var showNewPeriod = false
    @State private var showGenerate = false
    @State private var pendingConfirm: ConfirmAction?

    var body: some View {
        List {
            if store.db.periods.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有账期", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("账期是一段发薪 / 消费周期。新建或按模板生成后，就能看到每期额度。")
                    }
                    .clearListRowBackground()
                }
            } else {
                ForEach(store.sortedPeriods) { period in
                    Section {
                        Button {
                            editingPeriod = period
                        } label: {
                            PeriodRow(period: period)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingPeriod = period
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingConfirm = .deletePeriod(period)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showGenerate = true
                } label: {
                    Label("按模板自动生成账期", systemImage: "wand.and.stars")
                }
                Button {
                    showNewPeriod = true
                } label: {
                    Label("手动新建账期", systemImage: "plus.circle")
                }
            }

            if !store.db.periods.isEmpty {
                Section("危险操作") {
                    Button(role: .destructive) {
                        pendingConfirm = .deleteFuture
                    } label: {
                        Label("删除未开始的账期", systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        pendingConfirm = .clearAll
                    } label: {
                        Label("清空全部账期", systemImage: "trash.fill")
                    }
                }
            }
        }
        .appListStyle()
        .navigationTitle("账期")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewPeriod = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建账期")
            }
        }
        .sheet(isPresented: $showNewPeriod) {
            PeriodEditorSheet(period: nil)
        }
        .sheet(item: $editingPeriod) { period in
            PeriodEditorSheet(period: period)
        }
        .sheet(isPresented: $showGenerate) {
            GeneratePeriodsSheet()
        }
        .alert(
            confirmTitle,
            isPresented: confirmBinding,
            presenting: pendingConfirm
        ) { action in
            switch action {
            case .deleteFuture:
                Button("删除", role: .destructive) {
                    let count = store.deleteFuturePeriods()
                    store.showToast(count > 0 ? "已删除 \(count) 个账期" : "没有未开始的账期")
                }
            case .clearAll:
                Button("清空", role: .destructive) {
                    store.clearAllPeriods()
                    store.showToast("已清空全部账期")
                }
            case .deletePeriod(let period):
                Button("删除", role: .destructive) {
                    store.deletePeriod(id: period.id)
                    store.showToast("已删除账期")
                }
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            switch action {
            case .deleteFuture:
                Text("删除所有未开始的账期？其下支出记录会保留但不再计入额度。")
            case .clearAll:
                Text("清空全部 \(store.db.periods.count) 个账期？支出记录会保留但不再计入额度，此操作不可恢复。")
            case .deletePeriod(let period):
                Text("删除账期「\(period.name)」？其下支出记录会保留但不再计入额度。")
            }
        }
    }

    private var confirmTitle: String {
        switch pendingConfirm {
        case .deleteFuture: "删除未开始的账期"
        case .clearAll: "清空全部账期"
        case .deletePeriod(let period): "删除账期「\(period.name)」"
        case nil: ""
        }
    }
}

// MARK: - 账期卡片

extension PeriodsView {
    enum ConfirmAction {
        case deleteFuture
        case clearAll
        case deletePeriod(BudgetPeriod)
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirm != nil },
            set: { if !$0 { pendingConfirm = nil } }
        )
    }
}

struct PeriodRow: View {
    @Environment(BudgetStore.self) private var store
    let period: BudgetPeriod

    var body: some View {
        let today = DateX.today()
        let budget = store.periodBudget(period)
        let spent = store.periodSpent(period)
        let remain = store.periodRemain(period)
        let ratio = budget > 0 ? spent / budget : 1
        let status = today < period.start ? "未开始" : (today > period.end ? "已结束" : "进行中")
        let statusColor: Color = status == "进行中"
            ? (remain < 0 ? .red : (ratio >= 0.8 ? .orange : .green))
            : .secondary
        let percent = budget > 0 ? Int((ratio * 100).rounded()) : 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(period.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusChip(text: status, color: statusColor)
            }

            Text("\(period.start) ~ \(period.end)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("收入：\(incomeText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("固定：\(fixedText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                StatCell(title: "可支配", value: Money.string(budget))
                StatCell(
                    title: "剩余",
                    value: Money.string(remain),
                    valueColor: remain < 0 ? .red : .primary
                )
            }

            Text("已花 \(Money.string(spent))（\(percent)%）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var incomeText: String {
        period.incomes.isEmpty
            ? "无"
            : period.incomes.map { "\($0.label) \(Money.string($0.amount))" }.joined(separator: " · ")
    }

    private var fixedText: String {
        period.fixed.isEmpty
            ? "无"
            : period.fixed.map { "\($0.label) \(Money.string($0.amount))" }.joined(separator: " · ")
    }
}
