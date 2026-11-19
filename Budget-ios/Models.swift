import Foundation

// MARK: - 收支类型

enum EntryType: String, Codable, Hashable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var title: String { self == .income ? "收入" : "支出" }
}

// MARK: - 容错解码

/// 兼容数字 / 字符串两种写法（旧备份里金额可能是字符串）
struct FlexibleNumber: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            value = double
        } else {
            value = 0
        }
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        return ""
    }

    func lenientDouble(_ key: Key) -> Double {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string) ?? 0
        }
        return 0
    }

    func lenientOptionalString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        return nil
    }

    func lenientInts(_ key: Key) -> [Int] {
        guard let raw = try? decodeIfPresent([FlexibleNumber].self, forKey: key) else {
            return []
        }
        return raw.map { Int($0.value) }
    }
}

// MARK: - 账期里的收入 / 固定支出项

struct LedgerItem: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var amount: Double

    init(id: String = UUID().uuidString, label: String = "", amount: Double = 0) {
        self.id = id
        self.label = label
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, amount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = container.lenientString(.id)
        id = rawID.isEmpty ? UUID().uuidString : rawID
        label = container.lenientString(.label)
        amount = container.lenientDouble(.amount)
    }
}

// MARK: - 一条收支记录

struct ExpenseRecord: Codable, Identifiable, Hashable {
    var id: String
    var date: String          // YYYY-MM-DD（与 H5 一致的字符串日期）
    var amount: Double
    var type: EntryType
    var cat: String
    var note: String
    var periodId: String?     // nil = 不在任何账期内，不计入额度

    init(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        type: EntryType,
        cat: String,
        note: String = "",
        periodId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.type = type
        self.cat = cat
        self.note = note
        self.periodId = periodId
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, amount, type, cat, note, periodId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = container.lenientString(.id)
        id = rawID.isEmpty ? UUID().uuidString : rawID
        date = container.lenientString(.date)
        amount = container.lenientDouble(.amount)
        type = container.lenientString(.type) == EntryType.income.rawValue ? .income : .expense
        cat = container.lenientString(.cat)
        note = container.lenientString(.note)
        periodId = container.lenientOptionalString(.periodId)
        migrate()
    }

    /// 与 H5 相同的旧数据迁移：分类从备注里拆出来
    mutating func migrate() {
        if cat.isEmpty {
            let raw = note
            let legacyCategories = ["伙食", "房租", "月供", "交通", "日用", "社交", "其他"]
            if let hit = legacyCategories.first(where: { raw == $0 || raw.hasPrefix($0 + "·") }) {
                cat = hit
                note = raw == hit ? "" : String(raw.dropFirst(hit.count + 1))
            } else {
                cat = "其他"
            }
        }
        if date.isEmpty { date = DateX.today() }
    }
}

// MARK: - 账期

struct BudgetPeriod: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var start: String
    var end: String
    var incomes: [LedgerItem]
    var fixed: [LedgerItem]

    init(
        id: String = UUID().uuidString,
        name: String,
        start: String,
        end: String,
        incomes: [LedgerItem] = [],
        fixed: [LedgerItem] = []
    ) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.incomes = incomes
        self.fixed = fixed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, start, end, incomes, fixed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = container.lenientString(.id)
        id = rawID.isEmpty ? UUID().uuidString : rawID
        name = container.lenientString(.name)
        start = container.lenientString(.start)
        end = container.lenientString(.end)
        incomes = ((try? container.decodeIfPresent([LedgerItem].self, forKey: .incomes)) ?? nil) ?? []
        fixed = ((try? container.decodeIfPresent([LedgerItem].self, forKey: .fixed)) ?? nil) ?? []
        if start.isEmpty { start = DateX.today() }
        if end.isEmpty { end = start }
        if name.isEmpty { name = "\(DateX.md(start))~\(DateX.md(end))" }
    }

    var incomeTotal: Double { incomes.reduce(0) { $0 + $1.amount } }
    var fixedTotal: Double { fixed.reduce(0) { $0 + $1.amount } }
}

// MARK: - 固定收支模板

struct FixedRule: Codable, Identifiable, Hashable {
    var id: String
    var type: EntryType
    var label: String
    var amount: Double
    var days: [Int]           // 每月几号（可多个）
    var rangeStart: String    // 生效开始，空 = 一直有效
    var rangeEnd: String      // 生效结束，空 = 一直有效

    init(
        id: String = UUID().uuidString,
        type: EntryType,
        label: String,
        amount: Double,
        days: [Int],
        rangeStart: String = "",
        rangeEnd: String = ""
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.amount = amount
        self.days = days
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, label, amount, days, rangeStart, rangeEnd
        case legacyFrom = "from"
        case legacyTo = "to"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = container.lenientString(.id)
        id = rawID.isEmpty ? UUID().uuidString : rawID
        type = container.lenientString(.type) == EntryType.expense.rawValue ? .expense : .income
        label = container.lenientString(.label)
        amount = container.lenientDouble(.amount)
        days = container.lenientInts(.days).filter { (1...31).contains($0) }
        let start = container.lenientString(.rangeStart)
        rangeStart = start.isEmpty ? container.lenientString(.legacyFrom) : start
        let end = container.lenientString(.rangeEnd)
        rangeEnd = end.isEmpty ? container.lenientString(.legacyTo) : end
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(label, forKey: .label)
        try container.encode(amount, forKey: .amount)
        try container.encode(days, forKey: .days)
        try container.encode(rangeStart, forKey: .rangeStart)
        try container.encode(rangeEnd, forKey: .rangeEnd)
    }
}

// MARK: - 整份数据（与 H5 导出的 JSON 完全兼容）

struct BudgetDB: Codable {
    var periods: [BudgetPeriod]
    var rules: [FixedRule]
    var expenses: [ExpenseRecord]
    var updatedAt: String

    init(
        periods: [BudgetPeriod] = [],
        rules: [FixedRule] = [],
        expenses: [ExpenseRecord] = [],
        updatedAt: String = ""
    ) {
        self.periods = periods
        self.rules = rules
        self.expenses = expenses
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case periods, rules, expenses, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periods = ((try? container.decodeIfPresent([BudgetPeriod].self, forKey: .periods)) ?? nil) ?? []
        rules = ((try? container.decodeIfPresent([FixedRule].self, forKey: .rules)) ?? nil) ?? []
        expenses = ((try? container.decodeIfPresent([ExpenseRecord].self, forKey: .expenses)) ?? nil) ?? []
        updatedAt = container.lenientString(.updatedAt)
    }

    var isEmpty: Bool { periods.isEmpty && expenses.isEmpty }
}
