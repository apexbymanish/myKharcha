import Testing
import Foundation
@testable import KharchaKit

@Test func deleteCategoryReassignsTxnsToOther() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let cats = try await store.categories()
    let food = cats.first { $0.name == "Food" }!
    let other = cats.first { $0.name == "Other" }!

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    try await store.deleteCategory(categoryID: food.id)

    let otherSpend = try await store.spent(in: .month, categoryID: other.id, now: d(2026, 8, 14), calendar: testCal)
    #expect(otherSpend == 12_000)
    #expect(try await store.categories().contains { $0.name == "Food" } == false)
}

@Test func deletingOtherIsRejected() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let other = try await store.categories().first { $0.name == "Other" }!
    await #expect(throws: StoreError.invalidAmount) {
        try await store.deleteCategory(categoryID: other.id)
    }
}

@Test func deleteFriendBlockedByOpenDebt() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.friendHasOpenDebts) {
        try await store.deleteFriend(friendID: ram.id)
    }

    _ = try await store.settleDebt(debtID: debt.id, amount: 10_000)
    try await store.deleteFriend(friendID: ram.id) // now allowed
    #expect(try await store.friends().isEmpty)
}

@Test func deleteTxnRemovesIt() async throws {
    let store = try makeStore()
    let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual)
    try await store.deleteTxn(txnID: id)
    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 0)
}
