import Testing
import Foundation
@testable import KharchaKit

@Test func debtsForFriendIncludesSettledNewestFirst() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let old = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 7, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.settleDebt(debtID: old.id, amount: 10_000)

    let all = try await store.debts(friendID: ram.id)
    #expect(all.count == 2)
    #expect(all[0].amount == 20_000)      // newest first
    #expect(all[1].settled == true)        // settled included
}

@Test func updateTxnRewritesFields() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)

    try await store.updateTxn(txnID: id, amount: 7_500, kind: .expense, categoryID: food.id, note: "snack", date: d(2026, 8, 11))
    let row = try await store.txnRows().first { $0.id == id }!
    #expect(row.amount == 7_500)
    #expect(row.categoryName == "Food")
    #expect(row.note == "snack")
    #expect(row.date == d(2026, 8, 11))
}

@Test func updateTxnWithNilCategoryClearsExistingCategory() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)

    let before = try await store.txnRows().first { $0.id == id }!
    #expect(before.categoryName == "Food")

    try await store.updateTxn(txnID: id, amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10))

    let after = try await store.txnRows().first { $0.id == id }!
    #expect(after.categoryName == "")
}

@Test func updateTxnValidation() async throws {
    let store = try makeStore()
    let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)

    let nilNote: String? = nil
    await #expect(throws: StoreError.invalidAmount) {
        try await store.updateTxn(txnID: id, amount: 0, kind: TxnKind.expense, categoryID: nil, note: nilNote, date: d(2026, 8, 10))
    }

    await #expect(throws: StoreError.notFound) {
        try await store.updateTxn(txnID: UUID(), amount: 1, kind: TxnKind.expense, categoryID: nil, note: nilNote, date: d(2026, 8, 10))
    }

    await #expect(throws: StoreError.notFound) {
        try await store.updateTxn(txnID: id, amount: 1, kind: TxnKind.expense, categoryID: UUID(), note: nilNote, date: d(2026, 8, 10))
    }
}
