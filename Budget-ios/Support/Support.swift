import SwiftUI
import UniformTypeIdentifiers

// MARK: - 跨平台语义色

extension Color {
    /// 页面分组背景
    static var appGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// 卡片背景
    static var appCardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// 填充色（分类胶囊、输入框底）
    static var appFill: Color {
        #if os(iOS)
        Color(uiColor: .systemFill)
        #else
        Color.primary.opacity(0.07)
        #endif
    }

    /// 与 primary 互为反色的背景（用于 Toast）
    static var appSystemBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// MARK: - 跨平台修饰符

extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func appFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    @ViewBuilder
    func decimalPadKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func numbersKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.immediately)
        #else
        self
        #endif
    }

    /// iOS 用 detents 控制 sheet 高度，macOS 保持系统默认
    @ViewBuilder
    func largeSheet() -> some View {
        #if os(iOS)
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    @ViewBuilder
    func adaptiveSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    /// macOS 弹窗给一个合适的初始尺寸
    @ViewBuilder
    func macSheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 600)
        #else
        self
        #endif
    }

    /// 列表内透明行背景（macOS 无 listRowBackground）
    @ViewBuilder
    func clearListRowBackground() -> some View {
        #if os(iOS)
        listRowBackground(Color.clear)
        #else
        self
        #endif
    }

    /// iOS 上压缩列表分段间距（macOS 不提供该 API）
    @ViewBuilder
    func compactListSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
        #endif
    }

    /// 居中并限制内容宽度，适配 iPad 与 Mac 的大窗口
    func readableWidth(_ width: CGFloat = 640) -> some View {
        frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 日期工具（ISO 字符串与本地时区）

enum DateX {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func today() -> String { dayFormatter.string(from: Date()) }

    static func iso(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func nowStamp() -> String { stampFormatter.string(from: Date()) }

    static func parse(_ iso: String) -> Date? {
        if let date = dayFormatter.date(from: iso) { return date }
        if iso.count > 10, let date = dayFormatter.date(from: String(iso.prefix(10))) { return date }
        return nil
    }

    /// 兼容数字时间戳与 ISO 字符串，方便比较云端 / 本机新旧
    static func normalizedStamp(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        if let millis = Double(value), millis > 1_000_000_000_000 {
            return stampFormatter.string(from: Date(timeIntervalSince1970: millis / 1000))
        }
        return value
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let dateA = parse(a), let dateB = parse(b) else { return 0 }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dateA),
            to: calendar.startOfDay(for: dateB)
        ).day ?? 0
    }

    static func addDays(_ iso: String, _ days: Int) -> String {
        guard let date = parse(iso),
              let newDate = Calendar.current.date(byAdding: .day, value: days, to: date) else {
            return iso
        }
        return self.iso(newDate)
    }

    static func md(_ iso: String) -> String {
        guard let date = parse(iso) else { return iso }
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    static func ymd(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar.current
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }

    /// 周期推进：给定本期开始日，返回严格晚于它的下一个锚点日。
    /// 例如 anchors = [11, 24] 时按两次发薪日切分账期。
    static func nextAnchor(_ iso: String, anchors: [Int]) -> String? {
        guard let date = parse(iso) else { return nil }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let list = Array(Set(anchors.filter { (1...31).contains($0) })).sorted()
        guard !list.isEmpty else { return nil }

        for anchor in list {
            let candidate = ymd(
                year: year,
                month: month,
                day: min(anchor, daysInMonth(year: year, month: month))
            )
            if candidate > iso { return candidate }
        }
        let nextYear = month == 12 ? year + 1 : year
        let nextMonth = month == 12 ? 1 : month + 1
        return ymd(
            year: nextYear,
            month: nextMonth,
            day: min(list[0], daysInMonth(year: nextYear, month: nextMonth))
        )
    }
}

// MARK: - 金额格式化（与 H5 一致的 ¥1,234.56）

enum Money {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func string(_ value: Double) -> String {
        let magnitude = abs(value)
        let number = formatter.string(from: NSNumber(value: magnitude)) ?? String(format: "%.2f", magnitude)
        return (value < 0 ? "-" : "") + "¥" + number
    }

    static func plain(_ value: Double) -> String {
        let magnitude = abs(value)
        let number = formatter.string(from: NSNumber(value: magnitude)) ?? String(format: "%.2f", magnitude)
        return (value < 0 ? "-" : "") + number
    }
}

// MARK: - 分类字典（SF Symbols 版本）

struct LedgerCategory: Identifiable, Hashable {
    let key: String
    let symbol: String
    var id: String { key }
}

enum Categories {
    static let expense: [LedgerCategory] = [
        .init(key: "餐饮", symbol: "fork.knife"),
        .init(key: "零食", symbol: "birthday.cake.fill"),
        .init(key: "网购", symbol: "bag.fill"),
        .init(key: "交通", symbol: "car.fill"),
        .init(key: "转账", symbol: "arrow.left.arrow.right"),
        .init(key: "医疗", symbol: "cross.case.fill"),
        .init(key: "娱乐", symbol: "gamecontroller.fill"),
        .init(key: "其他", symbol: "sparkles"),
    ]

    static let income: [LedgerCategory] = [
        .init(key: "工资", symbol: "banknote.fill"),
        .init(key: "兼职", symbol: "briefcase.fill"),
        .init(key: "红包", symbol: "gift.fill"),
        .init(key: "理财", symbol: "chart.line.uptrend.xyaxis"),
        .init(key: "其他", symbol: "sparkles"),
    ]

    /// 旧版分类 → 图标兜底（老数据不改名）
    static let aliases: [String: String] = [
        "伙食": "fork.knife", "房租": "house.fill", "月供": "creditcard.fill",
        "买菜": "cart.fill", "通勤": "tram.fill", "日用": "basket.fill",
        "通讯": "iphone", "话费": "iphone", "社交": "person.2.fill",
        "订阅": "iphone", "宽带": "iphone", "还款": "creditcard.fill",
        "人情": "gift.fill", "学习": "book.fill", "借出": "hand.raised.fill",
        "借出垫付": "hand.raised.fill", "服饰": "tshirt.fill", "住房": "house.fill",
        "宠物": "pawprint.fill", "旅行": "airplane", "报销": "doc.text.fill",
        "奖金": "trophy.fill", "补贴": "ticket.fill", "退款": "arrow.uturn.backward",
    ]

    static func list(for type: EntryType) -> [LedgerCategory] {
        type == .income ? income : expense
    }

    static func symbol(for cat: String, type: EntryType) -> String {
        if let hit = (list(for: type) + expense + income).first(where: { $0.key == cat }) {
            return hit.symbol
        }
        return aliases[cat] ?? "sparkles"
    }

    /// 分类配色：扇形图与图例共用，未知分类落到灰色
    static func color(for cat: String) -> Color {
        switch cat {
        case "餐饮", "伙食":
            .orange
        case "零食", "社交", "人情":
            .pink
        case "网购", "日用":
            .purple
        case "交通", "通勤", "旅行":
            .blue
        case "转账", "借出", "借出垫付":
            .teal
        case "医疗":
            .red
        case "娱乐", "学习":
            .indigo
        case "房租", "住房", "月供", "还款":
            .brown
        case "通讯", "话费", "宽带", "订阅":
            .cyan
        case "买菜", "宠物":
            .green
        case "服饰":
            .mint
        default:
            .gray
        }
    }
}

// MARK: - 通用小组件

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appCardBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04))
        )
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct SyncChip: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol)
            Text(state.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .foregroundStyle(state.color)
        .background(state.color.opacity(0.14), in: Capsule())
    }
}

struct BarView: View {
    var value: Double          // 0...1
    var color: Color = .accentColor
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appFill)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 消费速率条：花费进度 + 时间进度刻度
struct RateBar: View {
    var spent: Double   // 0...1
    var time: Double    // 0...1
    var over: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appFill)
                Capsule()
                    .fill(over ? Color.red : Color.accentColor)
                    .frame(width: max(0, min(1, spent)) * proxy.size.width)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 2.5, height: proxy.size.height + 6)
                    .offset(x: max(0, min(1, time)) * proxy.size.width - 1.25)
            }
        }
        .frame(height: 10)
    }
}

struct StatCell: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color.appGroupedBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

struct WarningBox: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .padding(.top, 1)
            Text(text)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 表单提示（弹窗内的校验用原生 Alert，避免被 sheet 遮挡）

struct AlertMessageModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "提示",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func alertMessage(_ message: Binding<String?>) -> some View {
        modifier(AlertMessageModifier(message: message))
    }
}

// MARK: - 导出文件

nonisolated struct BudgetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 小工具

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension SyncState {
    var label: String {
        switch self {
        case .disabled: "未启用"
        case .idle: "检测中…"
        case .syncing: "同步中…"
        case .synced: "已同步"
        case .unavailable: "iCloud 不可用"
        case .error: "同步失败"
        }
    }

    var symbol: String {
        switch self {
        case .disabled: "icloud.slash"
        case .idle, .syncing: "icloud"
        case .synced: "checkmark.icloud"
        case .unavailable: "icloud.slash"
        case .error: "exclamationmark.icloud"
        }
    }

    var color: Color {
        switch self {
        case .disabled, .idle, .syncing, .unavailable: .secondary
        case .synced: .green
        case .error: .red
        }
    }
}
