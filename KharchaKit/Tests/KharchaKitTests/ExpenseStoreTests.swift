import Testing
import Foundation
@testable import KharchaKit

@Test func spentSumsOnlyExpensesInPeriod() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14, 18), source: .siri)
    _ = try await store.addTxn(amount: 99_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 1), source: .manual)  // earlier in month
    _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: "salary", date: d(2026, 8, 14), source: .manual) // income, excluded

    let today = try await store.spent(in: .today, categoryID: nil, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(today == 20_000)

    let month = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(month == 119_000)
}

@Test func spentFiltersByCategory() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_500, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 14), source: .manual)

    let foodOnly = try await store.spent(in: .today, categoryID: food.id, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(foodOnly == 12_000)
}

@Test func incomeSumsOnlyIncome() async throws {
    let store = try makeStore()
    _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)

    let month = try await store.income(in: .month, now: d(2026, 8, 14), calendar: testCal)
    #expect(month == 3_000_000)
}

@Test func zeroOrNegativeAmountRejected() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addTxn(amount: 0, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .siri)
    }
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addTxn(amount: -5, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .siri)
    }
}
