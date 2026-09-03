import Testing
import Foundation
@testable import KharchaKit

@Test func logExpenseSavesAndSpeaks() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let result = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: "lunch", now: d(2026, 8, 19), confirmedDuplicate: false)
    #expect(result.txnID != nil)
    #expect(!result.needsDuplicateConfirmation)
    #expect(result.message == "Logged ₩12,000 for Food.")
    let spent = try await store.spent(in: .today, categoryID: nil, now: d(2026, 8, 19), calendar: testCal)
    #expect(spent == 12_000)
}

@Test func duplicateAsksBeforeSavingTwice() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let now = d(2026, 8, 19)
    _ = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now.addingTimeInterval(-30), confirmedDuplicate: false)

    let second = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now, confirmedDuplicate: false)
    #expect(second.needsDuplicateConfirmation)
    #expect(second.txnID == nil)

    let confirmed = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now, confirmedDuplicate: true)
    #expect(confirmed.txnID != nil)
    let spent = try await store.spent(in: .today, categoryID: nil, now: now, calendar: testCal)
    #expect(spent == 24_000)
}

@Test func logExpenseRejectsBadAmount() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await LogExpenseHandler.run(store: store, amount: 0, categoryID: nil, categoryName: nil, note: nil, now: d(2026, 8, 19), confirmedDuplicate: false)
    }
}

@Test func logIncomeSaves() async throws {
    let store = try makeStore()
    let result = try await LogIncomeHandler.run(store: store, amount: 3_000_000, note: "salary", now: d(2026, 8, 19))
    #expect(result.message == "Recorded ₩3,000,000 income.")
    let income = try await store.income(in: .today, now: d(2026, 8, 19), calendar: testCal)
    #expect(income == 3_000_000)
}
