import Testing
import Foundation
@testable import KharchaKit

@Test func spendingSummaryOverall() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    _ = try await store.addTxn(amount: 42_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 19), source: .manual)
    _ = try await store.addTxn(amount: 700, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 19), source: .manual)

    let summary = try await SpendingQueryHandler.run(store: store, period: .today, categoryID: nil, categoryName: nil, now: d(2026, 8, 19, 20), calendar: testCal)
    #expect(summary.total == 42_700)
    #expect(summary.message == "You spent ₩42,700 today.")
    #expect(summary.top.first?.categoryName == "Food")
}

@Test func spendingSummaryForCategoryAndZeroSpend() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let summary = try await SpendingQueryHandler.run(store: store, period: .week, categoryID: food.id, categoryName: "Food", now: d(2026, 8, 19), calendar: testCal)
    #expect(summary.total == 0)
    #expect(summary.message == "You haven't spent anything this week.")

    _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 18), source: .manual)
    let summary2 = try await SpendingQueryHandler.run(store: store, period: .week, categoryID: food.id, categoryName: "Food", now: d(2026, 8, 19), calendar: testCal)
    #expect(summary2.message == "You spent ₩8,000 on Food this week.")
}

@Test func budgetReportMessages() async throws {
    let store = try makeStore()
    let empty = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(empty.message == "You haven't set any budgets yet.")

    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
    _ = try await store.addCategory(name: "Fun", symbol: "gamecontroller", colorHex: "#81B29A", monthlyBudget: 50_000)
    let ok = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(ok.message == "All 2 budgets are on track.")

    _ = try await store.addTxn(amount: 120_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
    let over = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(over.message == "1 of 2 budgets are over: Food.")
    #expect(over.statuses.count == 2)
}
