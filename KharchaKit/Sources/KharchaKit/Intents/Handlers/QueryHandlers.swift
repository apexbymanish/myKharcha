import Foundation

public struct SpendingSummary: Sendable, Equatable {
    public let periodLabel: String
    public let total: Decimal
    public let top: [CategorySpend]
    public let message: String
    public init(periodLabel: String, total: Decimal, top: [CategorySpend], message: String) {
        self.periodLabel = periodLabel
        self.total = total
        self.top = top
        self.message = message
    }
}

public enum SpendingQueryHandler {
    public static func label(for period: Period) -> String {
        switch period {
        case .today: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }

    public static func run(store: ExpenseStore, period: Period, categoryID: UUID?, categoryName: String?, now: Date, calendar: Calendar) async throws -> SpendingSummary {
        let periodLabel = label(for: period)
        if let categoryID {
            let total = try await store.spent(in: period, categoryID: categoryID, now: now, calendar: calendar)
            let message = total == 0
                ? "You haven't spent anything \(periodLabel)."
                : "You spent \(AmountFormatter.money(total)) on \(categoryName ?? "that") \(periodLabel)."
            return SpendingSummary(periodLabel: periodLabel, total: total, top: [], message: message)
        }
        let breakdown = try await store.spendingBreakdown(in: period, now: now, calendar: calendar)
        let message = breakdown.total == 0
            ? "You haven't spent anything \(periodLabel)."
            : "You spent \(AmountFormatter.money(breakdown.total)) \(periodLabel)."
        return SpendingSummary(periodLabel: periodLabel, total: breakdown.total, top: Array(breakdown.categories.prefix(3)), message: message)
    }
}

public struct BudgetReport: Sendable, Equatable {
    public let statuses: [BudgetStatus]
    public let message: String
    public init(statuses: [BudgetStatus], message: String) {
        self.statuses = statuses
        self.message = message
    }
}

public enum BudgetStatusHandler {
    public static func run(store: ExpenseStore, now: Date, calendar: Calendar) async throws -> BudgetReport {
        let statuses = try await store.budgetStatuses(now: now, calendar: calendar)
        guard !statuses.isEmpty else {
            return BudgetReport(statuses: [], message: "You haven't set any budgets yet.")
        }
        let over = statuses.filter(\.isOver)
        let message = over.isEmpty
            ? "All \(statuses.count) budgets are on track."
            : "\(over.count) of \(statuses.count) budgets are over: \(over.map(\.categoryName).joined(separator: ", "))."
        return BudgetReport(statuses: statuses, message: message)
    }
}
