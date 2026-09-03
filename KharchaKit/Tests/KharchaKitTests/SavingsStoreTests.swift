import Testing
import Foundation
@testable import KharchaKit

private let s1 = d(2026, 8, 1, 10)
private let s2 = d(2026, 8, 1, 11)

@Test func potBalanceIsSumOfLedgerEntries() async throws {
    let store = try makeStore()
    let pot = try await store.addSavingsPot(name: "Anonymous Bank", note: "rainy day")
    _ = try await store.addSavingsEntry(potID: pot.id, amount: 1_000_000, note: "Salary", date: d(2026, 8, 1))
    _ = try await store.addSavingsEntry(potID: pot.id, amount: -200_000, note: "Rent moved out", date: d(2026, 8, 2))

    let pots = try await store.savingsPots()
    #expect(pots.count == 1)
    #expect(pots[0].name == "Anonymous Bank")
    #expect(pots[0].balance == 800_000)          // 1,000,000 − 200,000
    #expect(try await store.totalSavings() == 800_000)
}

@Test func ledgerRecordsAreReturnedNewestFirst() async throws {
    let store = try makeStore()
    let pot = try await store.addSavingsPot(name: "Bank", note: nil)
    _ = try await store.addSavingsEntry(potID: pot.id, amount: 100, note: "older", date: d(2026, 8, 1))
    _ = try await store.addSavingsEntry(potID: pot.id, amount: 200, note: "newer", date: d(2026, 8, 5))

    let entries = try await store.savingsEntries(potID: pot.id)
    #expect(entries.count == 2)
    #expect(entries[0].note == "newer")          // newest first
    #expect(entries[1].note == "older")
}

@Test func upsertSavingsPotIsIdempotentAndNewestWins() async throws {
    let store = try makeStore()
    let id = UUID()
    try await store.upsertSavingsPot(id: id, name: "Old", note: nil, updatedAt: s1)
    try await store.upsertSavingsPot(id: id, name: "New", note: "n", updatedAt: s2)
    var pots = try await store.savingsPots()
    #expect(pots.count == 1)
    #expect(pots[0].name == "New")

    // Older write must not clobber.
    try await store.upsertSavingsPot(id: id, name: "Older", note: nil, updatedAt: s1)
    pots = try await store.savingsPots()
    #expect(pots[0].name == "New")
}

@Test func deletePotTombstonesPotAndItsEntries() async throws {
    let store = try makeStore()
    let pot = try await store.addSavingsPot(name: "Bank", note: nil)
    let entry = try await store.addSavingsEntry(potID: pot.id, amount: 500, note: nil, date: d(2026, 8, 1))

    try await store.deleteSavingsPot(id: pot.id)

    #expect(try await store.savingsPots().isEmpty)
    let tombs = try await store.exportTombstones()
    #expect(tombs.contains { $0.id == pot.id && $0.collection == "savingsPots" })
    #expect(tombs.contains { $0.id == entry.id && $0.collection == "savingsEntries" })
}

@Test func goalsCRUD() async throws {
    let store = try makeStore()
    _ = try await store.addSavingsGoal(name: "Emergency", targetAmount: 400_000, priority: 1)
    let goals = try await store.savingsGoals()
    #expect(goals.count == 1)
    #expect(goals[0].name == "Emergency")
    #expect(goals[0].targetAmount == 400_000)
}

@Test @MainActor func savingsViewModelBuildsAllocationFromPotsAndRules() async throws {
    let store = try makeStore()
    let pot = try await store.addSavingsPot(name: "Bank", note: nil)
    _ = try await store.addSavingsEntry(potID: pot.id, amount: 1_000_000, note: nil, date: d(2026, 8, 1))
    _ = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 3, autoLog: false)

    let vm = SavingsViewModel(store: store)
    await vm.load()

    #expect(vm.state.totalBalance == 1_000_000)
    let allocation = try #require(vm.state.allocation)
    #expect(allocation.lines.first { $0.name == "Rent" }?.reserved == 500_000)
    #expect(allocation.free == 500_000)
    #expect(allocation.isFullyFunded)
}
