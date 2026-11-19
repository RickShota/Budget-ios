import SwiftUI

@main
struct MyApp: App {
    @State private var store = BudgetStore()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            root
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记一笔") {
                    store.selectedTab = .add
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    store.selectedTab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("前往") {
                Button("概览") { store.selectedTab = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("记一笔") { store.selectedTab = .add }
                    .keyboardShortcut("2", modifiers: .command)
                Button("账期") { store.selectedTab = .periods }
                    .keyboardShortcut("3", modifiers: .command)
                Button("设置") { store.selectedTab = .settings }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }
        #else
        WindowGroup {
            root
        }
        #endif
    }

    private var root: some View {
        ContentView()
            .environment(store)
            .tint(.blue)
    }
}
