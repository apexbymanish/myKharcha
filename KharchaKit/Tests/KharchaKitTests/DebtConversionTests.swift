import Testing
import Foundation
@testable import KharchaKit

@Test func convertMakesExpenseOfRemainingAndSettles() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.settleDebt(debtID: debt.id, amount: 20_000) // partially repaid

    _ = try await store.convertDebtToExpense(debtID: debt.id, date: d(2026, 8, 14))

    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 30_000) // only the unpaid remainder becomes an expense

    let open = try await store.openDebts()
    #expect(open.isEmpty)

    let net = try await store.netBalance(friendID: ram.id)
    #expect(net == 0)
}

@Test func convertTookDebtIsRejected() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    let debt = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.convertDebtToExpense(debtID: debt.id, date: d(2026, 8, 14))
    }
}
