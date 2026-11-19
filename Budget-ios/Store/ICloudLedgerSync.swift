import Foundation

// MARK: - iCloud 同步错误

enum ICloudSyncError: LocalizedError {
    case tooLarge
    case encodeFailed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            "账本数据超过 iCloud 键值存储上限（1 MB），暂时只能保存在本机"
        case .encodeFailed:
            "账本数据编码失败"
        case .unavailable:
            "iCloud 同步不可用（未登录 iCloud，或当前签名未启用 iCloud 能力）"
        }
    }
}

/// 基于 iCloud 键值存储（NSUbiquitousKeyValueStore）的备份与同步。
/// 整本账以压缩后的 JSON 存入 iCloud，同一 Apple 账户的设备会自动同步。
@MainActor
final class ICloudLedgerSync {
    /// 单条键值上限 1 MB，预留空间
    private static let maxPayloadBytes = 900_000

    private static let storageKey = "budget-ledger-v1"

    private let store = NSUbiquitousKeyValueStore.default
    private let onRemoteChange: (BudgetDB?) -> Void
    /// 已登录 iCloud 且当前签名确实具备键值存储能力
    private(set) var isUsable: Bool

    init(onRemoteChange: @escaping (BudgetDB?) -> Void) {
        self.onRemoteChange = onRemoteChange
        isUsable = Self.checkAvailability()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleExternalChange(notification)
            }
        }
    }

    /// 重新检测 iCloud 可用性（登录状态或签名能力可能在运行中变化）
    @discardableResult
    func refreshAvailability() -> Bool {
        isUsable = Self.checkAvailability()
        return isUsable
    }

    /// 注意：没有 iCloud entitlement 时 ubiquityIdentityToken 仍可能非空，
    /// 因此必须同时验证键值存储同步是否真的可用。
    private static func checkAvailability() -> Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        return NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - 读写

    func read() -> BudgetDB? {
        guard isUsable, let payload = store.data(forKey: Self.storageKey) else { return nil }
        let json = Self.decompress(payload) ?? payload
        return try? JSONDecoder().decode(BudgetDB.self, from: json)
    }

    func write(_ db: BudgetDB) throws {
        guard isUsable else { throw ICloudSyncError.unavailable }
        guard let json = try? JSONEncoder().encode(db) else {
            throw ICloudSyncError.encodeFailed
        }
        let payload = Self.compress(json)
        guard payload.count <= Self.maxPayloadBytes else {
            throw ICloudSyncError.tooLarge
        }
        store.set(payload, forKey: Self.storageKey)
        if !store.synchronize() {
            isUsable = false
            throw ICloudSyncError.unavailable
        }
    }

    // MARK: - 外部变更

    private func handleExternalChange(_ notification: Notification) {
        let isAccountChange = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int)
            == NSUbiquitousKeyValueStoreAccountChange
        if isAccountChange {
            refreshAvailability()
        }

        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        if !isAccountChange, let changedKeys, !changedKeys.contains(Self.storageKey) {
            return
        }
        onRemoteChange(read())
    }

    // MARK: - 压缩（减小 iCloud 键值体积）

    private static func compress(_ data: Data) -> Data {
        guard let compressed = try? (data as NSData).compressed(using: .zlib) else {
            return data
        }
        return compressed as Data
    }

    private static func decompress(_ data: Data) -> Data? {
        guard let decompressed = try? (data as NSData).decompressed(using: .zlib) else {
            return nil
        }
        return decompressed as Data
    }
}
