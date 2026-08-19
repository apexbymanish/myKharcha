import Testing
import Foundation
@testable import KharchaKit

@Test func breakdownSumsAndRanksCategories() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 30_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .siri)
    _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 700, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual) // excluded
    _ = try await store.addTxn(amount: 99_999, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 1), source: .manual)  // out of period

    let breakdown = try await store.spendingBreakdown(in: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(breakdown.total == 47_700)
    #expect(breakdown.categories.map(\.categoryName) == ["Food", "Transport", "Uncategorized"])
    #expect(breakdown.categories[0].amount == 42_000)
}

@Test func emptyStoreBreakdownIsZero() async throws {
    let store = try makeStore()
    let breakdown = try await store.spendingBreakdown(in: .today, now: d(2026, 8, 15), calendar: testCal)
    #expect(breakdown.total == 0)
    #expect(breakdown.categories.isEmpty)
}
