import Testing
import Foundation
@testable import KharchaKit

@Test func seedInsertsDefaultsOnce() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    try await store.seedDefaultCategoriesIfNeeded() // idempotent
    let names = try await store.categories().map(\.name)
    #expect(names.count == 10)
    #expect(names.contains("Food"))
    #expect(names.contains("Rent"))
    #expect(names.contains("Salary"))   // income default
    #expect(names.contains("Other"))
}

@Test func budgetStatusReportsMonthToDateSpendAndOverrun() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
    let fun = try await store.addCategory(name: "Entertainment", symbol: "gamecontroller", colorHex: "#81B29A", monthlyBudget: 50_000)
    _ = try await store.addCategory(name: "NoBudget", symbol: "tag", colorHex: "#999999", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 120_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 3), source: .manual)
    _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: fun.id, note: nil, date: d(2026, 8, 10), source: .manual)
    _ = try await store.addTxn(amount: 999_999, kind: .expense, categoryID: fun.id, note: nil, date: d(2026, 7, 10), source: .manual) // last month

    let statuses = try await store.budgetStatuses(now: d(2026, 8, 14), calendar: testCal)
    #expect(statuses.count == 2) // only categories with budgets

    let foodStatus = statuses.first { $0.categoryName == "Food" }!
    #expect(foodStatus.spent == 120_000)
    #expect(foodStatus.isOver)

    let funStatus = statuses.first { $0.categoryName == "Entertainment" }!
    #expect(funStatus.spent == 10_000)
    #expect(!funStatus.isOver)
}

@Test func setBudgetUpdatesCategory() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    try await store.setBudget(categoryID: food.id, amount: 200_000)
    let statuses = try await store.budgetStatuses(now: d(2026, 8, 14), calendar: testCal)
    #expect(statuses.first?.budget == 200_000)
}
