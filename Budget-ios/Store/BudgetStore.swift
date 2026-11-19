import Foundation
import Observation

// MARK: - 标签页

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case add
    case periods
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "概览"
        case .add: "记一笔"
        case .periods: "账期"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .add: "plus.circle.fill"
        case .periods: "calendar"
        case .settings: "gearshape.fill"
        }
    }

    /// macOS 侧边栏使用描边图标，视觉更轻
    var sidebarSymbol: String {
        switch self {
        case .home: "house"
        case .add: "plus.circle"
        case .periods: "calendar"
        case .settings: "gearshape"
        }
    }
}

// MARK: - 同步状态

enum SyncState: Equatable {
    case disabled
    case idle
    case syncing
    case synced
    case unavailable
    case error
}

// MARK: - 数据与业务逻辑（对应 H5 的 db + 计算函数）

@Observable
@MainActor
final class BudgetStore {
    // 数据
    var db: BudgetDB
    // UI 状态
    var selectedTab: AppTab = .home
    var toastText: String?
    var syncState: SyncState = .disabled

    // 同步配置（持久化到 UserDefaults）
    var iCloudEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudEnabled, forKey: Keys.enabled)
            if iCloudEnabled {
                Task { await syncOnLaunch() }
            } else {
                pushTask?.cancel()
                syncState = .disabled
            }
        }
    }
    var lastSyncedAt: Date? {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: Keys.lastSyncedAt) }
    }
    var syncErrorMessage: String?

    var iCloudAvailable: Bool { cloud?.isUsable ?? false }

    private enum Keys {
        static let enabled = "budget.icloudEnabled"
        static let lastSyncedAt = "budget.lastSyncedAt"
    }

    private var pushTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var cloud: ICloudLedgerSync!

    // MARK: - 初始化

    init() {
        let defaults = UserDefaults.standard
        iCloudEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        lastSyncedAt = defaults.object(forKey: Keys.lastSyncedAt) as? Date
        db = Self.loadFromDisk() ?? BudgetDB()
        cloud = ICloudLedgerSync { [weak self] remote in
            self?.handleRemoteChange(remote)
        }
        if !iCloudEnabled {
            syncState = .disabled
        } else if !cloud.isUsable {
            syncState = .unavailable
        }
    }

    // MARK: - 本机持久化（对应 localStorage）

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("budget-ledger.json")
    }

    private static func loadFromDisk() -> BudgetDB? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BudgetDB.self, from: data)
    }

    private func saveLocal() {
        do {
            let data = try JSONEncoder().encode(db)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[BudgetStore] save failed:", error)
        }
    }

    /// 任何修改：更新时间戳 → 落本机 → 稍后防抖上传 iCloud
    func commit() {
        db.updatedAt = DateX.nowStamp()
        saveLocal()
        scheduleCloudPush()
    }

    // MARK: - 提示

    func showToast(_ message: String) {
        toastText = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toastText = nil
        }
    }

    // MARK: - 账期计算

    var sortedPeriods: [BudgetPeriod] {
        db.periods.sorted { $0.start < $1.start }
    }

    func findPeriod(date: String) -> BudgetPeriod? {
        sortedPeriods.first { date >= $0.start && date <= $0.end }
    }

    func currentPeriod() -> BudgetPeriod? {
        let today = DateX.today()
        let list = sortedPeriods
        if let hit = list.first(where: { today >= $0.start && today <= $0.end }) { return hit }
        if let upcoming = list.first(where: { $0.start > today }) { return upcoming }
        return list.last
    }

    func periodIncome(_ period: BudgetPeriod) -> Double { period.incomeTotal }

    func periodFixed(_ period: BudgetPeriod) -> Double { period.fixedTotal }

    /// 记账时随手补记的收入（补贴、报销、红包等），计入可支配额度
    func periodExtraIncome(_ period: BudgetPeriod) -> Double {
        db.expenses
            .filter { $0.periodId == period.id && $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    func periodBudget(_ period: BudgetPeriod) -> Double {
        periodIncome(period) + periodExtraIncome(period) - periodFixed(period)
    }

    func periodSpent(_ period: BudgetPeriod) -> Double {
        db.expenses
            .filter { $0.periodId == period.id && $0.type != .income }
            .reduce(0) { $0 + $1.amount }
    }

    func periodRemain(_ period: BudgetPeriod) -> Double {
        periodBudget(period) - periodSpent(period)
    }

    struct RateInfo {
        let total: Int
        let passed: Int
        let left: Int
        let budget: Double
        let spent: Double
        let remain: Double
        let perDay: Double
        let expectPerDay: Double
        let projected: Double
        let spentPct: Double
        let timePct: Double
    }

    /// 消费速率：按已过天数的日均支出，外推本账期期末余额
    func rateInfo(_ period: BudgetPeriod) -> RateInfo {
        let today = DateX.today()
        let total = max(1, DateX.daysBetween(period.start, period.end) + 1)
        let passed = min(total, max(1, DateX.daysBetween(period.start, today) + 1))
        let left = max(0, total - passed)
        let budget = periodBudget(period)
        let spent = periodSpent(period)
        let remain = periodRemain(period)
        let perDay = spent / Double(passed)
        let expectPerDay = budget > 0 ? budget / Double(total) : 0
        return RateInfo(
            total: total,
            passed: passed,
            left: left,
            budget: budget,
            spent: spent,
            remain: remain,
            perDay: perDay,
            expectPerDay: expectPerDay,
            projected: remain - perDay * Double(left),
            spentPct: budget > 0 ? (spent / budget) * 100 : 100,
            timePct: (Double(passed) / Double(total)) * 100
        )
    }

    struct CategoryStat: Identifiable {
        let cat: String
        let amount: Double
        var id: String { cat }
    }

    /// 本期分类统计：这个账期的钱花在哪儿
    func categoryStats(for period: BudgetPeriod) -> [CategoryStat] {
        var sums: [String: Double] = [:]
        for expense in db.expenses where expense.periodId == period.id && expense.type != .income {
            let key = expense.cat.isEmpty ? "其他" : expense.cat
            sums[key, default: 0] += expense.amount
        }
        return sums
            .map { CategoryStat(cat: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - 记录增删改

    func addExpense(date: String, amount: Double, type: EntryType, cat: String, note: String) {
        let period = findPeriod(date: date)
        db.expenses.append(
            ExpenseRecord(
                date: date,
                amount: amount,
                type: type,
                cat: cat,
                note: note,
                periodId: period?.id
            )
        )
        commit()
    }

    func updateExpense(id: String, date: String, amount: Double, type: EntryType, cat: String, note: String) {
        guard let index = db.expenses.firstIndex(where: { $0.id == id }) else { return }
        let period = findPeriod(date: date)
        db.expenses[index].date = date
        db.expenses[index].amount = amount
        db.expenses[index].type = type
        db.expenses[index].cat = cat
        db.expenses[index].note = note
        db.expenses[index].periodId = period?.id
        commit()
    }

    func deleteExpense(id: String) {
        db.expenses.removeAll { $0.id == id }
        commit()
    }

    // MARK: - 账期增删改

    func upsertPeriod(_ period: BudgetPeriod, isNew: Bool) {
        if isNew {
            db.periods.append(period)
        } else if let index = db.periods.firstIndex(where: { $0.id == period.id }) {
            db.periods[index] = period
        }
        commit()
    }

    func deletePeriod(id: String) {
        db.periods.removeAll { $0.id == id }
        for index in db.expenses.indices where db.expenses[index].periodId == id {
            db.expenses[index].periodId = nil
        }
        commit()
    }

    /// 返回删除的账期数量
    @discardableResult
    func deleteFuturePeriods() -> Int {
        let today = DateX.today()
        let list = sortedPeriods.filter { $0.start > today }
        guard !list.isEmpty else { return 0 }
        let ids = Set(list.map(\.id))
        db.periods.removeAll { ids.contains($0.id) }
        for index in db.expenses.indices {
            if let periodId = db.expenses[index].periodId, ids.contains(periodId) {
                db.expenses[index].periodId = nil
            }
        }
        commit()
        return list.count
    }

    @discardableResult
    func clearAllPeriods() -> Int {
        let count = db.periods.count
        db.periods = []
        for index in db.expenses.indices {
            db.expenses[index].periodId = nil
        }
        commit()
        return count
    }

    // MARK: - 模板增删改

    func upsertRule(_ rule: FixedRule, isNew: Bool) {
        if isNew {
            db.rules.append(rule)
        } else if let index = db.rules.firstIndex(where: { $0.id == rule.id }) {
            db.rules[index] = rule
        }
        commit()
    }

    func deleteRule(id: String) {
        db.rules.removeAll { $0.id == id }
        commit()
    }

    // MARK: - 模板 → 账期

    /// 默认锚点：取金额较大的收入日期（小额进账不作为周期分界）
    func defaultAnchors() -> String {
        let incomeRules = db.rules.filter { $0.type == .income }
        guard !incomeRules.isEmpty else { return "24" }
        let maxAmount = incomeRules.map(\.amount).max() ?? 0
        let bigRules = incomeRules.filter { $0.amount >= maxAmount * 0.3 }
        let source = bigRules.isEmpty ? incomeRules : bigRules
        let days = Array(Set(source.flatMap(\.days))).sorted()
        return days.isEmpty ? "24" : days.map { String($0) }.joined(separator: ",")
    }

    /// 某段日期内会发生的模板收支
    func rulesForPeriod(start: String, end: String, type: EntryType) -> [LedgerItem] {
        guard let startDate = DateX.parse(start), let endDate = DateX.parse(end), start <= end else {
            return []
        }
        let calendar = Calendar.current
        var year = calendar.component(.year, from: startDate)
        var month = calendar.component(.month, from: startDate)
        let endYear = calendar.component(.year, from: endDate)
        let endMonth = calendar.component(.month, from: endDate)

        var months: [(year: Int, month: Int)] = []
        var guardCounter = 0
        while (year < endYear || (year == endYear && month <= endMonth)) && guardCounter < 36 {
            months.append((year, month))
            if month == 12 {
                month = 1
                year += 1
            } else {
                month += 1
            }
            guardCounter += 1
        }

        var result: [LedgerItem] = []
        for rule in db.rules where rule.type == type {
            let hit = months.contains { ym in
                let dim = DateX.daysInMonth(year: ym.year, month: ym.month)
                return rule.days.contains { day in
                    let iso = DateX.ymd(year: ym.year, month: ym.month, day: min(day, dim))
                    let inPeriod = iso >= start && iso <= end
                    let afterStart = rule.rangeStart.isEmpty || iso >= rule.rangeStart
                    let beforeEnd = rule.rangeEnd.isEmpty || iso <= rule.rangeEnd
                    return inPeriod && afterStart && beforeEnd
                }
            }
            if hit {
                result.append(LedgerItem(label: rule.label, amount: rule.amount))
            }
        }
        return result
    }

    /// 按模板自动生成账期，返回新建的数量
    @discardableResult
    func generatePeriods(start: String, anchors: [Int], count: Int, tag: String) -> Int {
        var cursor = start
        var created = 0
        let limit = max(1, min(24, count))
        for _ in 0..<limit {
            guard let next = DateX.nextAnchor(cursor, anchors: anchors), next > cursor else { break }
            let end = DateX.addDays(next, -1)
            if !db.periods.contains(where: { $0.start == cursor }) {
                let tagText = tag.isEmpty ? "" : "（\(tag)）"
                let name = "\(DateX.md(cursor))~\(DateX.md(end))\(tagText)"
                db.periods.append(
                    BudgetPeriod(
                        name: name,
                        start: cursor,
                        end: end,
                        incomes: rulesForPeriod(start: cursor, end: end, type: .income),
                        fixed: rulesForPeriod(start: cursor, end: end, type: .expense)
                    )
                )
                created += 1
            }
            cursor = next
        }
        if created > 0 { commit() }
        return created
    }

    // MARK: - 导入 / 导出 / 重置

    enum ImportError: Error {
        case invalid
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(db)
    }

    func importData(_ data: Data) throws {
        let object = try? JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any], dictionary["periods"] != nil else {
            throw ImportError.invalid
        }
        db = try JSONDecoder().decode(BudgetDB.self, from: data)
        commit()
    }

    func resetAllData() {
        db.periods = []
        db.expenses = []
        commit()
    }

    // MARK: - iCloud 同步

    private func scheduleCloudPush() {
        guard iCloudEnabled else { return }
        pushTask?.cancel()
        syncState = .syncing
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.pushToICloud()
        }
    }

    /// 启动时：先拉取云端，谁新用谁；云端为空则稍后上传本机数据
    func syncOnLaunch() async {
        guard iCloudEnabled else {
            syncState = .disabled
            return
        }
        guard cloud.refreshAvailability() else {
            syncState = .unavailable
            return
        }
        syncState = .idle
        await pullFromICloud()

        if cloud.read() == nil, !db.isEmpty {
            // 等首次 iCloud 下发完成，避免覆盖其他设备上的数据
            try? await Task.sleep(for: .seconds(2))
            if cloud.read() == nil {
                await pushToICloud()
            }
        }
    }

    func pushToICloud() async {
        guard iCloudEnabled else {
            syncState = .disabled
            return
        }
        guard cloud.isUsable else {
            syncState = .unavailable
            return
        }
        syncState = .syncing
        do {
            try cloud.write(db)
            markSynced()
        } catch {
            syncErrorMessage = error.localizedDescription
            syncState = .error
        }
    }

    /// 拉取云端数据：时间戳较新的一方胜出
    func pullFromICloud(manual: Bool = false) async {
        guard iCloudEnabled else {
            syncState = .disabled
            return
        }
        guard cloud.refreshAvailability() else {
            syncState = .unavailable
            if manual { showToast("iCloud 同步不可用，请检查 iCloud 登录或 App 签名能力") }
            return
        }
        syncState = .idle

        guard let remote = cloud.read() else {
            syncState = .synced
            if manual { showToast("iCloud 上还没有备份") }
            return
        }

        let remoteStamp = DateX.normalizedStamp(remote.updatedAt)
        let localStamp = DateX.normalizedStamp(db.updatedAt)

        if remoteStamp > localStamp {
            db = remote
            saveLocal()
            markSynced()
            showToast(manual ? "已从 iCloud 恢复" : "已同步 iCloud 上的最新数据")
        } else if localStamp > remoteStamp {
            await pushToICloud()
            if manual { showToast("本机数据较新，已上传到 iCloud") }
        } else {
            markSynced()
            if manual { showToast("已是最新") }
        }
    }

    /// 手动「从 iCloud 恢复（覆盖本机）」
    func restoreFromICloud() async {
        guard iCloudEnabled else {
            syncState = .disabled
            showToast("请先开启 iCloud 同步")
            return
        }
        guard cloud.refreshAvailability() else {
            syncState = .unavailable
            showToast("iCloud 同步不可用，请检查 iCloud 登录或 App 签名能力")
            return
        }
        guard let remote = cloud.read() else {
            syncState = .synced
            showToast("iCloud 上还没有备份")
            return
        }
        db = remote
        saveLocal()
        markSynced()
        showToast("已从 iCloud 恢复")
    }

    /// 其他设备写入 iCloud 后，系统会通知到这里
    private func handleRemoteChange(_ remote: BudgetDB?) {
        guard iCloudEnabled else { return }
        guard cloud.isUsable else {
            syncState = .unavailable
            return
        }
        guard let remote else { return }
        let remoteStamp = DateX.normalizedStamp(remote.updatedAt)
        let localStamp = DateX.normalizedStamp(db.updatedAt)

        if remoteStamp > localStamp {
            db = remote
            saveLocal()
            markSynced()
            showToast("已同步 iCloud 上的最新数据")
        } else if localStamp > remoteStamp {
            Task { await pushToICloud() }
        } else {
            markSynced()
        }
    }

    private func markSynced() {
        syncState = .synced
        syncErrorMessage = nil
        lastSyncedAt = Date()
    }
}
