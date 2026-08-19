import AppIntents
import KharchaKit

struct KharchaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogExpenseIntent(), phrases: [
            "Log an expense in \(.applicationName)",
            "Log \(\.$category) spending in \(.applicationName)",
            "I spent money in \(.applicationName)",
            "\(.applicationName) expense"
        ], shortTitle: "Log Expense", systemImageName: "minus.circle")

        AppShortcut(intent: LogIncomeIntent(), phrases: [
            "Log income in \(.applicationName)",
            "I got paid in \(.applicationName)",
            "\(.applicationName) income"
        ], shortTitle: "Log Income", systemImageName: "plus.circle")

        AppShortcut(intent: SpendingQueryIntent(), phrases: [
            "How much did I spend in \(.applicationName)",
            "\(.applicationName) spending",
            "Check my spending in \(.applicationName)"
        ], shortTitle: "Spending", systemImageName: "chart.bar")

        AppShortcut(intent: BudgetStatusIntent(), phrases: [
            "How is my budget in \(.applicationName)",
            "\(.applicationName) budget"
        ], shortTitle: "Budget", systemImageName: "gauge")

        AppShortcut(intent: AddReminderIntent(), phrases: [
            "Add a bill reminder in \(.applicationName)",
            "\(.applicationName) reminder"
        ], shortTitle: "Bill Reminder", systemImageName: "bell")

        AppShortcut(intent: LogDebtIntent(), phrases: [
            "Log a loan in \(.applicationName)",
            "I gave money to \(\.$friend) in \(.applicationName)",
            "I took money from \(\.$friend) in \(.applicationName)",
            "\(.applicationName) loan"
        ], shortTitle: "Log Loan", systemImageName: "person.badge.plus")

        AppShortcut(intent: SettleDebtIntent(), phrases: [
            "\(\.$friend) paid me back in \(.applicationName)",
            "Settle up in \(.applicationName)"
        ], shortTitle: "Settle Up", systemImageName: "checkmark.seal")

        AppShortcut(intent: DebtQueryIntent(), phrases: [
            "Who owes me money in \(.applicationName)",
            "\(.applicationName) debts"
        ], shortTitle: "Debts", systemImageName: "list.bullet.rectangle")
    }
}
