import Testing
import Foundation
import SwiftData
import KharchaKit

// Deliberately a PLAIN `import KharchaKit` (no @testable). This file exercises only the
// public surface a real app target would see. If it stops compiling, the public API
// has regressed (an internal init became required, a type stopped being public, etc).

private func publicTestDate(_ y: Int, _ m: Int, _ day: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return cal.date(from: DateComponents(timeZone: cal.timeZone, year: y, month: m, day: day, hour: 12))!
}

private func makePublicStore() throws -> ExpenseStore {
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ExpenseStore(modelContainer: container)
}

@Test func publicAPI_snapshotTypesAreDirectlyConstructible() {
    let friend = FriendSnapshot(id: UUID(), name: "Ram")
    #expect(friend.name == "Ram")

    let debt = DebtSnapshot(
        id: UUID(),
        friendID: friend.id,
        friendName: friend.name,
        amount: 10_000,
        direction: .iGave,
        remaining: 10_000,
        settled: false,
        dueDate: nil,
        date: publicTestDate(2026, 8, 1),
        note: "lunch"
    )
    #expect(debt.remaining == 10_000)

    let category = CategorySnapshot(
        id: UUID(),
        name: "Food",
        symbol: "fork.knife",
        colorHex: "#E07A5F",
        monthlyBudget: nil,
        isFallback: false
    )
    #expect(category.name == "Food")

    let budget = BudgetStatus(categoryID: category.id, categoryName: category.name, spent: 1_000, budget: 2_000)
    #expect(!budget.isOver)

    let row = TxnRow(id: UUID(), date: .now, kind: .expense, amount: 500, categoryName: "Food", note: nil, source: .manual)
    #expect(row.amount == 500)
}

@Test func publicAPI_seedAddCategoryAddTxnSpentFlow() async throws {
    let store = try makePublicStore()
    try await store.seedDefaultCategoriesIfNeeded()

    let food = try await store.addCategory(name: "Groceries", symbol: "cart", colorHex: "#123456", monthlyBudget: nil)
    _ = try await store.addTxn(
        amount: 5_000,
        kind: .expense,
        categoryID: food.id,
        note: "veggies",
        date: publicTestDate(2026, 8, 14),
        source: .manual
    )

    let spent = try await store.spent(in: .month, categoryID: food.id, now: publicTestDate(2026, 8, 14), calendar: Calendar(identifier: .gregorian))
    #expect(spent == 5_000)
}

@Test func publicAPI_moreSnapshotTypesAreDirectlyConstructible() {
    let rule = RecurringRuleSnapshot(
        id: UUID(), name: "Rent", amount: 500_000, categoryName: "Rent",
        dayOfMonth: 25, remindDaysBefore: 3, autoLog: false
    )
    #expect(rule.dayOfMonth == 25)

    let categorySpend = CategorySpend(categoryID: UUID(), categoryName: "Food", amount: 12_000)
    #expect(categorySpend.categoryName == "Food")

    let breakdown = SpendingBreakdown(total: 12_000, categories: [categorySpend])
    #expect(breakdown.total == 12_000)

    let logResult = LogResult(txnID: UUID(), needsDuplicateConfirmation: false, message: "Logged.")
    #expect(!logResult.needsDuplicateConfirmation)

    let summary = SpendingSummary(periodLabel: "today", total: 12_000, top: [categorySpend], message: "You spent ₩12,000 today.")
    #expect(summary.periodLabel == "today")

    let budgetStatus = BudgetStatus(categoryID: UUID(), categoryName: "Food", spent: 1_000, budget: 2_000)
    let report = BudgetReport(statuses: [budgetStatus], message: "All 1 budgets are on track.")
    #expect(report.statuses.count == 1)

    let row = DebtRow(friendID: UUID(), name: "Ram", amount: 20_000)
    #expect(row.name == "Ram")

    let overview = DebtOverview(theyOweMe: [row], iOwe: [], message: "1 friend owes you ₩20,000.")
    #expect(overview.theyOweMe.count == 1)

    let settleResult = SettleResult(settledAmount: 20_000, remainingOwed: 0, message: "Ram is all settled up.")
    #expect(settleResult.remainingOwed == 0)
}

@Test func publicAPI_addFriendAddDebtSettleDebtNetBalanceFlow() async throws {
    let store = try makePublicStore()
    let friend = try await store.addFriend(name: "Hari", phone: nil)
    let debt = try await store.addDebt(
        friendID: friend.id,
        amount: 20_000,
        direction: .iGave,
        date: publicTestDate(2026, 8, 1),
        note: nil,
        dueDate: nil
    )

    let afterSettle = try await store.settleDebt(debtID: debt.id, amount: 20_000)
    #expect(afterSettle.settled)

    let net = try await store.netBalance(friendID: friend.id)
    #expect(net == 0)
}
