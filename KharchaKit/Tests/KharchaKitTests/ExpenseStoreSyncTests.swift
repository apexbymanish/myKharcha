import Testing
import Foundation
@testable import KharchaKit

private let t1 = d(2026, 8, 1, 10)
private let t2 = d(2026, 8, 1, 11)  // newer than t1

@Test func upsertCategoryInsertsThenUpdatesPreservingID() async throws {
    let store = try makeStore()
    let id = UUID()
    try await store.upsertCategory(id: id, name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100, isFallback: false, updatedAt: t1)
    var cats = try await store.categories()
    #expect(cats.count == 1)
    #expect(cats[0].id == id)

    // Newer timestamp → updates in place, no duplicate.
    try await store.upsertCategory(id: id, name: "Groceries", symbol: "cart", colorHex: "#000000", monthlyBudget: 200, isFallback: false, updatedAt: t2)
    cats = try await store.categories()
    #expect(cats.count == 1)
    #expect(cats[0].name == "Groceries")
    #expect(cats[0].monthlyBudget == 200)
}

@Test func olderRemoteDoesNotClobberNewerLocal() async throws {
    let store = try makeStore()
    let id = UUID()
    try await store.upsertCategory(id: id, name: "Newer", symbol: "star", colorHex: "#111111", monthlyBudget: nil, isFallback: false, updatedAt: t2)
    // An OLDER remote write must not overwrite the newer local value.
    try await store.upsertCategory(id: id, name: "Older", symbol: "star", colorHex: "#222222", monthlyBudget: nil, isFallback: false, updatedAt: t1)
    let cats = try await store.categories()
    #expect(cats.count == 1)
    #expect(cats[0].name == "Newer")
}

@Test func upsertTxnResolvesCategoryAndIsIdempotent() async throws {
    let store = try makeStore()
    let catID = UUID()
    try await store.upsertCategory(id: catID, name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil, isFallback: false, updatedAt: t1)
    let txnID = UUID()
    try await store.upsertTxn(id: txnID, amount: 500, kind: .expense, categoryID: catID, note: "lunch", date: d(2026, 8, 1), source: .manual, updatedAt: t1)
    var rows = try await store.txnRows()
    #expect(rows.count == 1)
    #expect(rows[0].categoryName == "Food")

    // Newer re-upsert updates; no duplicate.
    try await store.upsertTxn(id: txnID, amount: 750, kind: .income, categoryID: nil, note: "refund", date: d(2026, 8, 1), source: .manual, updatedAt: t2)
    rows = try await store.txnRows()
    #expect(rows.count == 1)
    #expect(rows[0].amount == 750)
    #expect(rows[0].kind == .income)
}

@Test func exportTxnsCarriesCategoryID() async throws {
    let store = try makeStore()
    let cat = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    _ = try await store.addTxn(amount: 100, kind: .expense, categoryID: cat.id, note: nil, date: d(2026, 8, 1), source: .manual)
    let exports = try await store.exportTxns()
    #expect(exports.count == 1)
    #expect(exports[0].categoryID == cat.id)
}

@Test func upsertDebtPreservesSettlementAndFriend() async throws {
    let store = try makeStore()
    let fid = UUID()
    try await store.upsertFriend(id: fid, name: "Ram", phone: nil, updatedAt: t1)
    let did = UUID()
    try await store.upsertDebt(DebtExport(id: did, friendID: fid, amount: 100, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil, settledAmount: 40, settled: false, updatedAt: t1))
    var debts = try await store.debts(friendID: fid)
    #expect(debts.count == 1)
    #expect(debts[0].remaining == 60)

    try await store.upsertDebt(DebtExport(id: did, friendID: fid, amount: 100, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil, settledAmount: 100, settled: true, updatedAt: t2))
    debts = try await store.debts(friendID: fid)
    #expect(debts.count == 1)
    #expect(debts[0].settled == true)
}

@Test func deleteRecordsTombstone() async throws {
    let store = try makeStore()
    let txnID = try await store.addTxn(amount: 100, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .manual)
    try await store.deleteTxn(txnID: txnID)
    let tombs = try await store.exportTombstones()
    #expect(tombs.contains { $0.id == txnID && $0.collection == "txns" })
}

@Test func tombstoneBlocksOlderResurrectButAllowsNewer() async throws {
    let store = try makeStore()
    // Create + delete a txn at t1 → tombstone at ~now (later than t1).
    let id = UUID()
    try await store.upsertTxn(id: id, amount: 100, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .manual, updatedAt: t1)
    try await store.deleteTxn(txnID: id)
    #expect(try await store.txnRows().isEmpty)

    // An OLDER remote write must stay blocked by the deletion.
    try await store.upsertTxn(id: id, amount: 100, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .manual, updatedAt: t1)
    #expect(try await store.txnRows().isEmpty)

    // A write dated in the far future (after the deletion) resurrects it.
    try await store.upsertTxn(id: id, amount: 200, kind: .expense, categoryID: nil, note: "back", date: d(2026, 8, 1), source: .manual, updatedAt: d(2999, 1, 1))
    let rows = try await store.txnRows()
    #expect(rows.count == 1)
    #expect(rows[0].amount == 200)
}

@Test func applyRemoteTombstoneDeletesOlderLocal() async throws {
    let store = try makeStore()
    let id = UUID()
    try await store.upsertTxn(id: id, amount: 100, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .manual, updatedAt: t1)
    #expect(try await store.txnRows().count == 1)
    try await store.applyRemoteTombstone(id: id, collection: "txns", deletedAt: t2)
    #expect(try await store.txnRows().isEmpty)
}
