import Testing
import Foundation
@testable import KharchaKit

@Test func monthlyFromTotalSplitsEvenlyAndRounds() {
    #expect(InstallmentMath.monthlyFromTotal(1_200_000, termCount: 12, currencyCode: "KRW") == 100_000)
    // 1000 / 3 = 333.33… → whole won.
    #expect(InstallmentMath.monthlyFromTotal(1000, termCount: 3, currencyCode: "KRW") == 333)
    // USD keeps two minor units: 100 / 3 = 33.33.
    #expect(InstallmentMath.monthlyFromTotal(100, termCount: 3, currencyCode: "USD") == Decimal(string: "33.33")!)
    #expect(InstallmentMath.monthlyFromTotal(1000, termCount: 0, currencyCode: "KRW") == 0)
}

@Test func evaluateComputesBalanceAndProgress() {
    let s = InstallmentMath.evaluate(
        monthlyAmount: 100_000, termCount: 12, dayOfMonth: 5,
        payments: [100_000, 100_000],
        now: d(2026, 8, 1), calendar: testCal
    )
    #expect(s.totalCommitted == 1_200_000)
    #expect(s.paidAmount == 200_000)
    #expect(s.remainingAmount == 1_000_000)
    #expect(s.paidCount == 2)
    #expect(s.remainingCount == 10)
    #expect(!s.isComplete)
    #expect(abs(s.progress - (1.0 / 6.0)) < 0.001)   // 200k / 1.2M
    #expect(s.payoffAmount == 1_000_000)
}

@Test func evaluateMarksCompleteWhenFullyPaid() {
    let s = InstallmentMath.evaluate(
        monthlyAmount: 100_000, termCount: 3, dayOfMonth: 1,
        payments: [100_000, 100_000, 100_000],
        now: d(2026, 8, 1), calendar: testCal
    )
    #expect(s.remainingAmount == 0)
    #expect(s.isComplete)
    #expect(s.progress == 1)
    #expect(s.remainingCount == 0)
}

@Test func evaluateFloorsRemainingOnOverpayment() {
    let s = InstallmentMath.evaluate(
        monthlyAmount: 100_000, termCount: 3, dayOfMonth: 1,
        payments: [250_000, 100_000],   // paid more than the 300k total
        now: d(2026, 8, 1), calendar: testCal
    )
    #expect(s.remainingAmount == 0)
    #expect(s.isComplete)
    #expect(s.progress == 1)
}

@Test func evaluateNextDueDateRollsPastToday() {
    // Due on the 3rd. On Aug 1 the next due is Aug 3.
    let a = InstallmentMath.evaluate(monthlyAmount: 100_000, termCount: 12, dayOfMonth: 3,
                                     payments: [], now: d(2026, 8, 1), calendar: testCal)
    #expect(a.nextDueDate == d(2026, 8, 3, 0))
    // On Aug 5 (past the 3rd) the next due rolls to Sep 3.
    let b = InstallmentMath.evaluate(monthlyAmount: 100_000, termCount: 12, dayOfMonth: 3,
                                     payments: [], now: d(2026, 8, 5), calendar: testCal)
    #expect(b.nextDueDate == d(2026, 9, 3, 0))
}
