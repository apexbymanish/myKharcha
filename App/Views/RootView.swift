import SwiftUI
import KharchaKit

/// Tab root: Home / History / Friends / More. "More" is a List pushing
/// Budgets, Reminders, Settings (Task 9 brief §Interfaces). `AppServices` is
/// read once here (the only place a plain `@EnvironmentObject` is used) and
/// its `store` is threaded explicitly into each screen's initializer — leaf
/// screens never touch `AppServices` or the store directly, only their own
/// ViewModel (see task-9-report.md, "adaptations").
struct RootView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(store: services.store)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                HistoryView(store: services.store)
            }
            .tabItem { Label("History", systemImage: "list.bullet") }

            NavigationStack {
                FriendsView(store: services.store)
            }
            .tabItem { Label("Friends", systemImage: "person.2") }

            NavigationStack {
                MoreView(store: services.store)
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

private struct MoreView: View {
    let store: ExpenseStore

    var body: some View {
        List {
            NavigationLink("Budgets") { BudgetsView(store: store) }
            NavigationLink("Reminders") { RemindersView(store: store) }
            NavigationLink("Settings") { SettingsView(store: store) }
        }
        .navigationTitle("More")
    }
}
