import Testing
import Foundation
@testable import KharchaKit

@Test func netBalanceCombinesGaveAndTook() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)

    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let net = try await store.netBalance(friendID: ram.id)
    #expect(net == 30_000) // Ram owes me 30,000
}

@Test func partialSettleReducesRemaining() async throws {
    let store = try makeStore()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    let debt = try await store.addDebt(friendID: sita.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    let afterPartial = try await store.settleDebt(debtID: debt.id, amount: 20_000)
    #expect(afterPartial.remaining == 30_000)
    #expect(!afterPartial.settled)

    let afterFull = try await store.settleDebt(debtID: debt.id, amount: 30_000)
    #expect(afterFull.remaining == 0)
    #expect(afterFull.settled)

    let net = try await store.netBalance(friendID: sita.id)
    #expect(net == 0)
}

@Test func overSettleThrows() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.settleDebt(debtID: debt.id, amount: 10_001)
    }
}

@Test func debtsDoNotAffectSpendingOrIncome() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 14), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 14), note: nil, dueDate: nil)

    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    let income = try await store.income(in: .month, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 0)
    #expect(income == 0)
}

@Test func openDebtsListsUnsettledOldestFirst() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let old = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 7, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.settleDebt(debtID: old.id, amount: 10_000)

    let open = try await store.openDebts()
    #expect(open.count == 1)
    #expect(open.first?.amount == 20_000)
}

@Test func settleFriendDebtsITookOldestFirstWithPartial() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    // Two "I took" debts (I owe Ram) — oldest first should be drained first.
    _ = try await store.addDebt(friendID: ram.id, amount: 30_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let (settled, remaining) = try await store.settleFriendDebts(friendID: ram.id, amount: 35_000, direction: .iTook)
    #expect(settled == 35_000)
    #expect(remaining == 15_000)

    let open = try await store.openDebts()
    #expect(!open.contains { $0.date == d(2026, 8, 1) })
    let newer = try #require(open.first { $0.date == d(2026, 8, 5) })
    #expect(newer.remaining == 15_000)

    // Fully settle the remaining .iTook debt.
    _ = try await store.settleFriendDebts(friendID: ram.id, amount: nil, direction: .iTook)

    // .iGave debts of the same friend must be untouched by an .iTook settle,
    // and once no open .iTook debts remain, settling .iTook again is .notFound.
    _ = try await store.addDebt(friendID: ram.id, amount: 5_000, direction: .iGave, date: d(2026, 8, 10), note: nil, dueDate: nil)
    await #expect(throws: StoreError.notFound) {
        _ = try await store.settleFriendDebts(friendID: ram.id, amount: nil, direction: .iTook)
    }
    let net = try await store.netBalance(friendID: ram.id)
    #expect(net == 5_000) // only the untouched .iGave debt remains
}
