import SwiftUI

struct HomeView: View {
    @Environment(BudgetStore.self) private var store

    @State private var showNewPeriod = false
    @State private var showGenerate = false
    @State private var didCheckPrompt = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let period = store.currentPeriod() {
                    content(for: period)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("概览")
        .sheet(isPresented: $showNewPeriod) {
            PeriodEditorSheet(period: nil)
        }
        .sheet(isPresented: $showGenerate) {
            GeneratePeriodsSheet()
        }
        .onAppear(perform: checkPeriodPrompt)
    }

    // MARK: - 主体

    @ViewBuilder
    private func content(for period: BudgetPeriod) -> some View {
        let today = DateX.today()
        let inPeriod = today >= period.start && today <= period.end
        let budget = store.periodBudget(period)
        let spent = store.periodSpent(period)
        let remain = store.periodRemain(period)
        let ratio = budget > 0 ? spent / budget : 1
        let barColor: Color = remain < 0 ? .red : (ratio >= 0.8 ? .orange : .accentColor)
        let daysLeft = max(1, DateX.daysBetween(today, period.end) + (inPeriod ? 1 : 0))
        let daily = remain / Double(daysLeft)
        let statusText = remain < 0 ? "已超支" : (ratio >= 0.8 ? "接近上限" : "健康")
        let statusColor: Color = remain < 0 ? .red : (ratio >= 0.8 ? .orange : .green)

        if remain < 0 {
            WarningBox(
                color: .red,
                text: "本期已超支 \(Money.string(-remain))！管住手，能不花就不花。"
            )
        } else if ratio >= 0.8 {
            WarningBox(
                color: .orange,
                text: "本期额度已用 \(Int((ratio * 100).rounded()))%，只剩 \(Money.string(remain))，接下来悠着点。"
            )
        }

        Card {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("当前账期 · \(period.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                if store.iCloudEnabled, store.syncState != .unavailable {
                    SyncChip(state: store.syncState)
                }
                StatusChip(text: statusText, color: statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("剩余可支配")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Money.string(remain))
                    .font(.system(size: heroFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(remain < 0 ? Color.red : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            BarView(value: min(1, max(0, ratio)), color: barColor)

            HStack {
                Text("已花 \(Money.string(spent))")
                Spacer()
                Text("额度 \(Money.string(budget))")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                StatCell(
                    title: inPeriod ? "日均可用" : "距开始",
                    value: inPeriod ? "\(Money.string(daily))/天" : period.start
                )
                StatCell(
                    title: inPeriod ? "剩余天数" : "账期区间",
                    value: inPeriod ? "\(daysLeft) 天" : period.end
                )
            }
        }

        if today >= period.start {
            rateSection(for: period)
        }

        categorySection(for: period)

        Button {
            store.selectedTab = .add
        } label: {
            Label("记一笔", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 2)
    }

    // MARK: - 消费速率

    @ViewBuilder
    private func rateSection(for period: BudgetPeriod) -> some View {
        let info = store.rateInfo(period)
        let over = info.projected < 0
        let keepPerDay = info.left > 0 ? max(0, info.remain / Double(info.left)) : 0

        SectionTitle("消费速率")

        Card {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("日均花销")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.string(info.perDay))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(over ? Color.red : Color.green)
                Text("/ 期望 \(Money.string(info.expectPerDay))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            RateBar(
                spent: info.spentPct / 100,
                time: info.timePct / 100,
                over: over
            )

            HStack {
                Text("时间已过 \(Int(info.timePct.rounded()))%（\(info.passed)/\(info.total) 天）")
                Spacer()
                Text("花费已用 \(Int(min(100, info.spentPct).rounded()))%")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if over {
                WarningBox(
                    color: .red,
                    text: "照这个速度，本账期结束将超支 \(Money.string(-info.projected))。"
                        + (info.left > 0
                           ? "剩余 \(info.left) 天，每天控制在 \(Money.string(keepPerDay)) 以内才能守住额度。"
                           : "本期已结束。")
                )
            } else {
                WarningBox(
                    color: .green,
                    text: "照这个速度，本账期结束预计还剩 \(Money.string(info.projected))"
                        + (info.left > 0
                           ? "，剩余 \(info.left) 天平均每天可花 \(Money.string(keepPerDay))。"
                           : "。")
                )
            }
        }
    }

    // MARK: - 本期分类统计

    @ViewBuilder
    private func categorySection(for period: BudgetPeriod) -> some View {
        let stats = store.categoryStats(for: period)

        SectionTitle("本期分类统计")

        Card {
            if stats.isEmpty {
                Text("本期还没有支出记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                let total = stats.reduce(0) { $0 + $1.amount }
                let maxValue = stats.map(\.amount).max() ?? 1

                VStack(spacing: 13) {
                    ForEach(stats) { stat in
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: Categories.symbol(for: stat.cat, type: .expense))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(stat.cat)
                                    .font(.subheadline)
                                Spacer()
                                Text(Money.string(stat.amount))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Text("\(Int((stat.amount / total * 100).rounded()))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                            BarView(value: max(0.04, stat.amount / maxValue), color: .accentColor, height: 6)
                        }
                    }

                    Divider()

                    HStack {
                        Text("共 \(stats.count) 个分类")
                        Spacer()
                        Text("合计 \(Money.string(total))")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有账期", systemImage: "calendar.badge.plus")
        } description: {
            Text("创建一个账期，填入收入和固定支出，就能开始管理预算。")
        } actions: {
            Button("创建第一个账期") {
                showNewPeriod = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    // MARK: - 账期遗漏提醒

    /// 今天不在任何账期内、且模板里有收入时，引导用户按模板生成账期
    private func checkPeriodPrompt() {
        guard !didCheckPrompt else { return }
        didCheckPrompt = true
        let list = store.sortedPeriods
        let today = DateX.today()
        guard let first = list.first,
              first.start <= today,
              !list.contains(where: { today >= $0.start && today <= $0.end }),
              store.db.rules.contains(where: { $0.type == .income }) else {
            return
        }
        store.showToast("今天不在任何账期内，建议按模板生成")
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            showGenerate = true
        }
    }
}
