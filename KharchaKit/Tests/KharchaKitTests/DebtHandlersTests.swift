import Testing
import Foundation
@testable import KharchaKit

@Test func logDebtSpeaksNetBalance() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let first = try await LogDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 50_000, direction: .iGave, note: nil, now: d(2026, 8, 19))
    #expect(first.message == "Noted — Ram owes you ₩50,000 (total ₩50,000).")
    let second = try await LogDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 80_000, direction: .iTook, note: nil, now: d(2026, 8, 19))
    #expect(second.message == "Noted — you owe Ram ₩80,000 (total ₩30,000).")
}

@Test func settleAllAndPartial() async throws {
    let store = try makeStore()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 30_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iGave, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let partial = try await SettleDebtHandler.run(store: store, friendID: sita.id, friendName: "Sita", amount: 40_000, now: d(2026, 8, 19))
    #expect(partial.settledAmount == 40_000)
    #expect(partial.remainingOwed == 10_000)
    #expect(partial.message == "Settled ₩40,000 — Sita still owes you ₩10,000.")

    let full = try await SettleDebtHandler.run(store: store, friendID: sita.id, friendName: "Sita", amount: nil, now: d(2026, 8, 19))
    #expect(full.message == "Sita is all settled up.")
    #expect(try await store.netBalance(friendID: sita.id) == 0)
}

@Test func settleValidation() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    await #expect(throws: StoreError.notFound) {
        _ = try await SettleDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: nil, now: d(2026, 8, 19))
    }
    _ = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await SettleDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 10_001, now: d(2026, 8, 19))
    }
}

@Test func debtOverviewSplitsDirections() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let overview = try await DebtQueryHandler.run(store: store)
    #expect(overview.theyOweMe.map(\.categoryName) == ["Ram"])
    #expect(overview.iOwe.first?.amount == 20_000)
    #expect(overview.message == "Friends owe you ₩50,000; you owe ₩20,000.")

    let empty = try await DebtQueryHandler.run(store: try makeStore())
    #expect(empty.message == "No open debts.")
}
