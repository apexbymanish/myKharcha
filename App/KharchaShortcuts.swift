import AppIntents
import SwiftUI
import KharchaKit

/// Process-wide bridge from an App Intent to SwiftUI navigation. `OpenAddExpenseIntent`
/// runs in the app process (openAppWhenRun) and flips `showAddExpense`; `RootView`
/// observes this singleton and presents the add-transaction form. This is the
/// reliable "tap the shortcut → add an expense" path that doesn't depend on Siri's
/// parameter-prompt UI (which `LogExpenseIntent`'s required `amount` needs).
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()
    @Published var showAddExpense = false
    private init() {}

    /// The Control Center control can't pass a URL, so it drops a flag in the
    /// shared App Group defaults and opens the app; we consume it on activation.
    private static let pendingKey = "pendingAddExpense"

    func consumePendingAddExpense() {
        let defaults = UserDefaults(suiteName: KharchaContainerFactory.appGroupID)
        if defaults?.bool(forKey: Self.pendingKey) == true {
            defaults?.set(false, forKey: Self.pendingKey)
            showAddExpense = true
        }
    }

    /// Handles the widget's `jebkharcha://add` deep link.
    func handle(url: URL) {
        if url.scheme == "jebkharcha", url.host == "add" {
            showAddExpense = true
        }
    }
}

/// Opens jebkharcha directly to the add-expense form. Unlike `LogExpenseIntent`,
/// this takes no parameters, so tapping it in Spotlight/Siri always does something
/// visible even when Siri can't render a value prompt.
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Opens Jeb Kharcha to add an expense.")
    static var openAppWhenRun: Bool { true }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.showAddExpense = true
        return .result()
    }
}

struct KharchaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenAddExpenseIntent(), phrases: [
            "Add a new expense in \(.applicationName)",
            "Open \(.applicationName) to log",
            "Quick add in \(.applicationName)"
        ], shortTitle: "Add Expense", systemImageName: "plus.circle.fill")

        AppShortcut(intent: LogExpenseIntent(), phrases: [
            "Log an expense in \(.applicationName)",
            "Add an expense in \(.applicationName)",
            "Record an expense in \(.applicationName)",
            "New expense in \(.applicationName)",
            "Log \(\.$category) spending in \(.applicationName)",
            "Track a \(\.$category) expense in \(.applicationName)",
            "I spent money in \(.applicationName)",
            "\(.applicationName) expense"
        ], shortTitle: "Log Expense", systemImageName: "minus.circle")

        AppShortcut(intent: LogIncomeIntent(), phrases: [
            "Log income in \(.applicationName)",
            "Add income in \(.applicationName)",
            "Record income in \(.applicationName)",
            "I got paid in \(.applicationName)",
            "I received money in \(.applicationName)",
            "\(.applicationName) income"
        ], shortTitle: "Log Income", systemImageName: "plus.circle")

        AppShortcut(intent: SpendingQueryIntent(), phrases: [
            "How much did I spend in \(.applicationName)",
            "How much have I spent in \(.applicationName)",
            "Check my spending in \(.applicationName)",
            "Show my spending in \(.applicationName)",
            "What did I spend on \(\.$category) in \(.applicationName)",
            "\(.applicationName) spending"
        ], shortTitle: "Spending", systemImageName: "chart.bar")

        AppShortcut(intent: BudgetStatusIntent(), phrases: [
            "How is my budget in \(.applicationName)",
            "How are my budgets in \(.applicationName)",
            "Check my budget in \(.applicationName)",
            "Am I over budget in \(.applicationName)",
            "\(.applicationName) budget"
        ], shortTitle: "Budget", systemImageName: "gauge")

        AppShortcut(intent: AddReminderIntent(), phrases: [
            "Add a bill reminder in \(.applicationName)",
            "Add a reminder in \(.applicationName)",
            "Remind me about a bill in \(.applicationName)",
            "New bill reminder in \(.applicationName)",
            "\(.applicationName) reminder"
        ], shortTitle: "Bill Reminder", systemImageName: "bell")

        AppShortcut(intent: LogDebtIntent(), phrases: [
            "Log a loan in \(.applicationName)",
            "Add a loan in \(.applicationName)",
            "I gave money to \(\.$friend) in \(.applicationName)",
            "I lent money to \(\.$friend) in \(.applicationName)",
            "I took money from \(\.$friend) in \(.applicationName)",
            "I borrowed money from \(\.$friend) in \(.applicationName)",
            "\(.applicationName) loan"
        ], shortTitle: "Log Loan", systemImageName: "person.badge.plus")

        AppShortcut(intent: SettleDebtIntent(), phrases: [
            "\(\.$friend) paid me back in \(.applicationName)",
            "I paid back \(\.$friend) in \(.applicationName)",
            "Settle up in \(.applicationName)",
            "Settle a debt in \(.applicationName)"
        ], shortTitle: "Settle Up", systemImageName: "checkmark.seal")

        AppShortcut(intent: DebtQueryIntent(), phrases: [
            "Who owes me money in \(.applicationName)",
            "Who do I owe in \(.applicationName)",
            "Show my debts in \(.applicationName)",
            "\(.applicationName) debts"
        ], shortTitle: "Debts", systemImageName: "list.bullet.rectangle")
    }
}
