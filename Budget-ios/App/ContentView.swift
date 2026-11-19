import SwiftUI

struct ContentView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        root
            .overlay(alignment: .bottom) {
                ToastView()
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .task {
                await store.syncOnLaunch()
            }
    }

    // MARK: - 平台根视图

    #if os(macOS)
    private var root: some View { macRoot }
    #else
    private var root: some View { iosRoot }
    #endif

    #if os(iOS)
    private var iosRoot: some View {
        @Bindable var store = store

        return TabView(selection: $store.selectedTab) {
            Tab("概览", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("记一笔", systemImage: "plus.circle.fill", value: AppTab.add) {
                NavigationStack { AddEntryView() }
            }
            Tab("账期", systemImage: "calendar", value: AppTab.periods) {
                NavigationStack { PeriodsView() }
            }
            Tab("设置", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }
    #endif

    #if os(macOS)
    private var macRoot: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.sidebarSymbol)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                if store.iCloudEnabled {
                    HStack {
                        SyncChip(state: store.syncState)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        } detail: {
            NavigationStack {
                page(for: store.selectedTab)
                    .frame(minWidth: 560, minHeight: 480)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { store.selectedTab },
            set: { if let tab = $0 { store.selectedTab = tab } }
        )
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .add: AddEntryView()
        case .periods: PeriodsView()
        case .settings: SettingsView()
        }
    }
    #endif
}

// MARK: - Toast

struct ToastView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Group {
            if let text = store.toastText {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.appSystemBackground)
                    .background(Color.primary, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: store.toastText)
        .allowsHitTesting(false)
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        74
        #else
        24
        #endif
    }
}

#Preview {
    ContentView()
        .environment(BudgetStore())
        .tint(.blue)
}
