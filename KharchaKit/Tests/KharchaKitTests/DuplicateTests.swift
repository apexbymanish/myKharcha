import Testing
import Foundation
@testable import KharchaKit

@Test func sameAmountCategoryWithin2MinutesIsDuplicate() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let now = d(2026, 8, 14, 12)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil,
                               date: now.addingTimeInterval(-60), source: .siri)

    #expect(try await store.isDuplicate(amount: 12_000, categoryID: food.id, now: now))
    #expect(try await store.isDuplicate(amount: 13_000, categoryID: food.id, now: now) == false)   // different amount
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: nil, now: now) == false)       // different category
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: food.id,
                                        now: now.addingTimeInterval(600)) == false)                // too old
}

@Test func manualEntriesNeverCountAsDuplicates() async throws {
    let store = try makeStore()
    let now = d(2026, 8, 14, 12)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: nil, note: nil,
                               date: now.addingTimeInterval(-30), source: .manual)
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: nil, now: now) == false)
}
