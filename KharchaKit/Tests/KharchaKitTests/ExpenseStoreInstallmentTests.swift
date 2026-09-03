import Testing
import Foundation
@testable import KharchaKit

@MainActor
struct ExpenseStoreInstallmentTests {

    private func addPhone(_ store: ExpenseStore, term: Int = 12) async throws -> InstallmentSnapshot {
        try await store.addInstallment(
            name: "iPhone", kind: .purchase, monthlyAmount: 100_000, termCount: term,
            dayOfMonth: 5, startDate: d(2026, 8, 1), categoryID: nil, remindDaysBefore: 3,
            autoLog: false, recordPrincipalAsIncome: false, note: nil,
            now: d(2026, 8, 1), calendar: testCal
        )
    }

    @Test func addAndListDerivesBalance() async throws {
        let store = try makeStore()
        _ = try await addPhone(store)
        let list = try await store.installments(now: d(2026, 8, 1), calendar: testCal)
        #expect(list.count == 1)
        let i = list[0]
        #expect(i.monthlyAmount == 100_000)
        #expect(i.paidAmount == 0)
        #expect(i.remainingAmount == 1_200_000)
        #expect(i.isActive)
        #expect(!i.isComplete)
    }

    @Test func recordPaymentCreatesExpenseAndAdvances() async throws {
        let store = try makeStore()
        let inst = try await addPhone(store)
        let after = try await store.recordInstallmentPayment(installmentID: inst.id, amount: 100_000, date: d(2026, 8, 5), now: d(2026, 8, 6), calendar: testCal)
        #expect(after.paidAmount == 100_000)
        #expect(after.remainingAmount == 1_100_000)
        #expect(after.paidCount == 1)

        // A real expense Txn was created (shows in history/spending).
        let rows = try await store.txnRows()
        #expect(rows.contains { $0.kind == .expense && $0.amount == 100_000 && $0.note == "iPhone" })
        let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 6), calendar: testCal)
        #expect(spent == 100_000)
    }

    @Test func payoffCompletesInstallment() async throws {
        let store = try makeStore()
        let inst = try await addPhone(store, term: 3)   // total 300k
        _ = try await store.recordInstallmentPayment(installmentID: inst.id, amount: 100_000, date: d(2026, 8, 5), now: d(2026, 8, 6), calendar: testCal)
        let done = try await store.payoffInstallment(installmentID: inst.id, date: d(2026, 8, 6), now: d(2026, 8, 7), calendar: testCal)
        #expect(done.remainingAmount == 0)
        #expect(done.isComplete)
        #expect(!done.isActive)
        // Two expense txns: the first payment + the payoff of the remaining 200k.
        let rows = try await store.txnRows().filter { $0.note == "iPhone" }
        #expect(rows.count == 2)
        #expect(rows.reduce(Decimal(0)) { $0 + $1.amount } == 300_000)
    }

    @Test func closeWithoutPayingCreatesNoExpense() async throws {
        let store = try makeStore()
        let inst = try await addPhone(store)
        let closed = try await store.closeInstallment(installmentID: inst.id, now: d(2026, 8, 6), calendar: testCal)
        #expect(closed.isClosed)
        #expect(!closed.isActive)
        #expect(try await store.txnRows().isEmpty)   // nothing was paid
    }

    @Test func deleteInstallmentTombstonesPlanButKeepsExpenses() async throws {
        let store = try makeStore()
        let inst = try await addPhone(store)
        _ = try await store.recordInstallmentPayment(installmentID: inst.id, amount: 100_000, date: d(2026, 8, 5), now: d(2026, 8, 6), calendar: testCal)
        try await store.deleteInstallment(id: inst.id)

        #expect(try await store.installments(now: d(2026, 8, 6), calendar: testCal).isEmpty)
        // The expense stays in history — the money was really spent.
        #expect(try await store.txnRows().contains { $0.amount == 100_000 && $0.note == "iPhone" })
        // Tombstone blocks a stale remote re-insert of the deleted plan.
        try await store.upsertInstallment(id: inst.id, name: "iPhone", kindRaw: "purchase", monthlyAmount: 100_000, termCount: 12, dayOfMonth: 5, startDate: d(2026, 8, 1), categoryID: nil, remindDaysBefore: 3, autoLog: false, recordPrincipalAsIncome: false, note: nil, isClosed: false, closedDate: nil, updatedAt: d(2026, 8, 1))
        #expect(try await store.installments(now: d(2026, 8, 6), calendar: testCal).isEmpty)
    }

    @Test func deletePaymentReversesTheExpense() async throws {
        let store = try makeStore()
        let inst = try await addPhone(store)
        _ = try await store.recordInstallmentPayment(installmentID: inst.id, amount: 100_000, date: d(2026, 8, 5), now: d(2026, 8, 6), calendar: testCal)
        let paymentID = try await store.installmentPayments(installmentID: inst.id)[0].id

        try await store.deleteInstallmentPayment(id: paymentID)
        #expect(try await store.txnRows().isEmpty)   // the expense was reversed
        let i = try await store.installments(now: d(2026, 8, 6), calendar: testCal)[0]
        #expect(i.paidAmount == 0)
        #expect(i.remainingAmount == 1_200_000)
    }

    @Test func loanWithPrincipalLogsIncome() async throws {
        let store = try makeStore()
        _ = try await store.addInstallment(
            name: "Bank loan", kind: .loan, monthlyAmount: 100_000, termCount: 10,
            dayOfMonth: 1, startDate: d(2026, 8, 1), categoryID: nil, remindDaysBefore: 3,
            autoLog: false, recordPrincipalAsIncome: true, note: nil,
            now: d(2026, 8, 1), calendar: testCal
        )
        let income = try await store.income(in: .month, now: d(2026, 8, 2), calendar: testCal)
        #expect(income == 1_000_000)   // monthly 100k × term 10
    }

    @Test func upsertNewestWins() async throws {
        let store = try makeStore()
        let id = UUID()
        func upsert(_ name: String, _ at: Date) async throws {
            try await store.upsertInstallment(id: id, name: name, kindRaw: "purchase", monthlyAmount: 100_000, termCount: 12, dayOfMonth: 5, startDate: d(2026, 8, 1), categoryID: nil, remindDaysBefore: 3, autoLog: false, recordPrincipalAsIncome: false, note: nil, isClosed: false, closedDate: nil, updatedAt: at)
        }
        try await upsert("First", d(2026, 8, 10))
        try await upsert("Older", d(2026, 8, 5))   // ignored (older)
        #expect(try await store.installments(now: d(2026, 8, 1), calendar: testCal)[0].name == "First")
        try await upsert("Newer", d(2026, 8, 20))  // applied
        #expect(try await store.installments(now: d(2026, 8, 1), calendar: testCal)[0].name == "Newer")
    }
}
