import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(BudgetStore.self) private var store

    @State private var showGenerate = false
    @State private var showNewRule = false
    @State private var editingRule: FixedRule?
    @State private var pendingConfirm: ConfirmAction?
    @State private var isExporting = false
    @State private var exportDocument: BudgetExportDocument?
    @State private var isImporting = false

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Toggle(isOn: $store.iCloudEnabled) {
                    Label("iCloud 同步", systemImage: "icloud")
                }

                if store.iCloudEnabled {
                    LabeledContent("同步状态") {
                        SyncChip(state: store.syncState)
                    }

                    if let lastSyncedAt = store.lastSyncedAt {
                        LabeledContent("上次同步") {
                            Text(lastSyncedAt, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !store.iCloudAvailable {
                        Label {
                            Text("iCloud 同步当前不可用（未登录 iCloud，或当前签名未启用 iCloud 能力）。数据只保存在本机。")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.icloud")
                        }
                        .foregroundStyle(.orange)
                    }

                    if store.syncState == .error, let message = store.syncErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await store.pullFromICloud(manual: true) }
                    } label: {
                        Label("立即同步", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!store.iCloudAvailable)

                    Button {
                        pendingConfirm = .restore
                    } label: {
                        Label("从 iCloud 恢复（覆盖本机）", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(!store.iCloudAvailable)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("数据通过 iCloud 在你的 iPhone、iPad 和 Mac 之间自动同步与备份，无需自建服务器。多台设备使用同一 Apple 账户登录即可；冲突时以更新时间较新的版本为准。")
            }

            Section {
                Button(action: prepareExport) {
                    Label("导出数据（JSON 备份）", systemImage: "square.and.arrow.up")
                }
                Button {
                    isImporting = true
                } label: {
                    Label("导入数据（恢复备份）", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    pendingConfirm = .reset
                } label: {
                    Label("清空所有数据", systemImage: "trash")
                }
            } header: {
                Text("数据")
            } footer: {
                Text("本机始终保留一份完整数据；开启 iCloud 后会额外备份到云端。换设备或长期不用前，仍建议导出一份文件备份。")
            }

            Section {
                if store.db.rules.isEmpty {
                    Text("还没有模板，点下方「新增模板」创建。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedRules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            RuleRow(rule: rule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    showNewRule = true
                } label: {
                    Label("新增模板", systemImage: "plus.circle")
                }
                Button {
                    showGenerate = true
                } label: {
                    Label("按模板自动生成账期", systemImage: "wand.and.stars")
                }
            } header: {
                Text("固定收支模板")
            } footer: {
                Text("工资、月供、房租这类固定收支，日期和金额填一次。之后可「按模板自动生成账期」，或在编辑账期时一键带入。点模板可编辑。")
            }

            Section("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("· 账期 = 一段发薪 / 消费周期，填入收入和固定支出后自动算出「可支配额度」")
                    Text("· 固定收支（工资、月供、房租）在模板里填一次，之后可自动生成账期")
                    Text("· 每天花 10 秒在「记一笔」里记录，剩余额度实时更新")
                    Text("· 用掉 80% 会变黄提醒，超支变红警告")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                Text("预算管家 · 原生 SwiftUI 版")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .appFormStyle()
        .readableWidth(760)
        .navigationTitle("设置")
        .sheet(isPresented: $showNewRule) {
            RuleEditorSheet(rule: nil)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rule: rule)
        }
        .sheet(isPresented: $showGenerate) {
            GeneratePeriodsSheet()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "预算管家备份-\(DateX.today())"
        ) { _ in }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .alert(
            pendingConfirm == .reset ? "清空所有数据" : "从 iCloud 恢复",
            isPresented: confirmBinding,
            presenting: pendingConfirm
        ) { action in
            switch action {
            case .restore:
                Button("恢复", role: .destructive) {
                    Task { await store.restoreFromICloud() }
                }
            case .reset:
                Button("清空", role: .destructive) {
                    store.resetAllData()
                    store.showToast("已清空账期和记录")
                }
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            switch action {
            case .restore:
                Text("用 iCloud 上的备份覆盖本机？本机尚未同步的修改会丢失。")
            case .reset:
                Text("确定清空所有账期和记录？此操作不可恢复，建议先导出备份。（固定收支模板会保留）")
            }
        }
    }

    enum ConfirmAction {
        case restore
        case reset
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirm != nil },
            set: { if !$0 { pendingConfirm = nil } }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var orderedRules: [FixedRule] {
        let income = store.db.rules.filter { $0.type == .income }
        let rest = store.db.rules.filter { $0.type != .income }
        return income + rest
    }

    private func prepareExport() {
        do {
            exportDocument = BudgetExportDocument(data: try store.exportData())
            isExporting = true
        } catch {
            store.showToast("导出失败")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                try store.importData(data)
                store.showToast("导入成功")
            } catch {
                store.showToast("文件格式不对")
            }
        case .failure:
            store.showToast("文件格式不对")
        }
    }
}

// MARK: - 模板卡片行

struct RuleRow: View {
    let rule: FixedRule

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    StatusChip(
                        text: rule.type == .income ? "收入" : "固定支出",
                        color: rule.type == .income ? .green : .orange
                    )
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.string(rule.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        var text = "每月 \(rule.days.map { String($0) }.joined(separator: "、")) 号"
        if !rule.rangeStart.isEmpty || !rule.rangeEnd.isEmpty {
            let start = rule.rangeStart.isEmpty ? "…" : DateX.md(rule.rangeStart)
            let end = rule.rangeEnd.isEmpty ? "至今" : DateX.md(rule.rangeEnd)
            text += " · \(start) ~ \(end) 生效"
        }
        return text
    }
}
