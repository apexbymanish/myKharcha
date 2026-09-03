import Testing
import Foundation
@testable import KharchaKit

@MainActor
@Test func activeInstallmentCountsAsMonthlyPlanCommitment() async throws {
    let store = try makeStore()
    let inst = try await store.addInstallment(
        name: "iPhone", kind: .purchase, monthlyAmount: 100_000, termCount: 12,
        dayOfMonth: 5, startDate: d(2026, 8, 1), categoryID: nil, remindDaysBefore: 3,
        autoLog: false, recordPrincipalAsIncome: false, note: nil, now: d(2026, 8, 1), calendar: testCal
    )
    let vm = MonthlyPlanViewModel(store: store)
    await vm.load(income: 3_000_000, savingsRatePercent: 20, now: d(2026, 8, 1), calendar: testCal)
    #expect(vm.state.commitments.contains { $0.name == "iPhone" && $0.amount == 100_000 })
    #expect(vm.state.plan?.commitmentsTotal == 100_000)

    // Once closed it stops being a commitment.
    _ = try await store.closeInstallment(installmentID: inst.id, now: d(2026, 8, 1), calendar: testCal)
    await vm.load(income: 3_000_000, savingsRatePercent: 20, now: d(2026, 8, 1), calendar: testCal)
    #expect(vm.state.plan?.commitmentsTotal == 0)
}

@MainActor
@Test func txnFormInstallmentModeCreatesInstallment() async throws {
    let store = try makeStore()   // pins KRW
    let vm = TxnFormViewModel(store: store)
    await vm.load()
    vm.setMode(.installment)
    vm.setInstName("iPhone")
    vm.setInstKind(.purchase)
    vm.setInstTotal("1200000")
    vm.setInstMonths(12)
    #expect(vm.state.instMonthlyText == "100000")   // total ÷ months, whole won
    vm.setInstDay(5)
    await vm.save()

    #expect(vm.state.didSave)
    let list = try await store.installments(now: d(2026, 8, 1), calendar: testCal)
    #expect(list.count == 1)
    #expect(list[0].name == "iPhone")
    #expect(list[0].monthlyAmount == 100_000)
    #expect(list[0].termCount == 12)
    #expect(list[0].dayOfMonth == 5)
}

private final class StubWatermark: AutoLogWatermark, @unchecked Sendable {
    var date: Date?
    init(_ d: Date?) { date = d }
    func lastRun() -> Date? { date }
    func setLastRun(_ d: Date) { date = d }
}

@MainActor
@Test func autoLogInstallmentRecordsDueOccurrencesIdempotently() async throws {
    let store = try makeStore()
    let inst = try await store.addInstallment(
        name: "iPhone", kind: .purchase, monthlyAmount: 100_000, termCount: 12,
        dayOfMonth: 5, startDate: d(2026, 1, 1), categoryID: nil, remindDaysBefore: 3,
        autoLog: true, recordPrincipalAsIncome: false, note: nil, now: d(2026, 1, 1), calendar: testCal
    )
    let wm = StubWatermark(d(2026, 6, 1))
    let n = try await AutoLogRunner.run(store: store, watermark: wm, now: d(2026, 8, 10), calendar: testCal)
    #expect(n == 3)   // due on the 5th: Jun 5, Jul 5, Aug 5
    #expect(try await store.installmentPayments(installmentID: inst.id).count == 3)

    // Rewinding the watermark must NOT double-record — ledger dedup guarantees it.
    wm.date = d(2026, 6, 1)
    let n2 = try await AutoLogRunner.run(store: store, watermark: wm, now: d(2026, 8, 10), calendar: testCal)
    #expect(n2 == 0)
}

@Test func installmentProducesDueReminder() {
    let inst = InstallmentSnapshot(
        id: UUID(), name: "iPhone", kind: .purchase, monthlyAmount: 100_000, termCount: 12,
        dayOfMonth: 10, startDate: d(2026, 8, 1), categoryID: nil, categoryName: "", remindDaysBefore: 3,
        autoLog: false, recordPrincipalAsIncome: false, note: nil, isClosed: false,
        paidAmount: 0, remainingAmount: 1_200_000, paidCount: 0, remainingCount: 12,
        progress: 0, nextDueDate: d(2026, 8, 10, 0), isComplete: false
    )
    let specs = ReminderPlanner.plan(rules: [], debts: [], installments: [inst], now: d(2026, 8, 1), calendar: testCal)
    #expect(specs.count == 1)
    #expect(specs[0].id == "installment-\(inst.id.uuidString)")
    #expect(specs[0].title == "iPhone")
    // Due the 10th, remind 3 days before at 9am → Aug 7 09:00.
    #expect(specs[0].fireDate == d(2026, 8, 7, 9))
}
