import Foundation

/// Whether a scheduled obligation is a purchase paid off in installments (a phone
/// EMI, a shop plan) or a loan you took and repay monthly. Both are monthly
/// outflows; the distinction only affects wording and the optional cash-in.
public enum InstallmentKind: String, Sendable, Codable, CaseIterable {
    case purchase
    case loan
}

/// The evaluated state of an installment: what's paid, what's left, when the next
/// payment is due, and whether it's finished. Pure value type — every figure is
/// exact (engine-computed), so the UI and sync never do money math.
public struct InstallmentStatus: Sendable, Equatable {
    /// monthlyAmount × termCount — the full amount you'll pay over the plan.
    public let totalCommitted: Decimal
    public let paidAmount: Decimal
    /// Remaining balance, floored at zero (overpayment can't go negative).
    public let remainingAmount: Decimal
    /// Number of payments recorded in the ledger.
    public let paidCount: Int
    /// Installments still expected (termCount − paidCount, floored at zero).
    public let remainingCount: Int
    /// Fraction paid, 0…1.
    public let progress: Double
    /// The next monthly due date, strictly after `now`.
    public let nextDueDate: Date
    /// True once the balance is fully paid off.
    public let isComplete: Bool

    public init(totalCommitted: Decimal, paidAmount: Decimal, remainingAmount: Decimal, paidCount: Int, remainingCount: Int, progress: Double, nextDueDate: Date, isComplete: Bool) {
        self.totalCommitted = totalCommitted
        self.paidAmount = paidAmount
        self.remainingAmount = remainingAmount
        self.paidCount = paidCount
        self.remainingCount = remainingCount
        self.progress = progress
        self.nextDueDate = nextDueDate
        self.isComplete = isComplete
    }

    /// What it would cost to clear the plan right now (== remaining balance).
    public var payoffAmount: Decimal { remainingAmount }
}

/// Pure installment evaluator. Given the terms and the payment ledger it computes
/// the balance, progress, and next due date. No arithmetic lives anywhere else.
public enum InstallmentMath {

    /// Evaluate an installment from its terms and the amounts recorded in its ledger.
    public static func evaluate(
        monthlyAmount: Decimal,
        termCount: Int,
        dayOfMonth: Int,
        payments: [Decimal],
        now: Date,
        calendar: Calendar = .current
    ) -> InstallmentStatus {
        let term = max(0, termCount)
        let total = monthlyAmount * Decimal(term)
        let paid = payments.reduce(Decimal(0), +)
        let remaining = max(0, total - paid)
        let paidCount = payments.count
        let remainingCount = max(0, term - paidCount)

        let progress: Double
        if total > 0 {
            let fraction = NSDecimalNumber(decimal: paid / total).doubleValue
            progress = min(1, max(0, fraction))
        } else {
            progress = paid > 0 ? 1 : 0
        }

        let nextDue = RecurringMath.nextDueDate(dayOfMonth: dayOfMonth, after: now, calendar: calendar)
        return InstallmentStatus(
            totalCommitted: total,
            paidAmount: paid,
            remainingAmount: remaining,
            paidCount: paidCount,
            remainingCount: remainingCount,
            progress: progress,
            nextDueDate: nextDue,
            isComplete: remaining <= 0
        )
    }

    /// The per-month amount from a `total` spread across `termCount` months, rounded
    /// to the currency's minor units (KRW/JPY → whole units).
    public static func monthlyFromTotal(_ total: Decimal, termCount: Int, currencyCode: String = AmountFormatter.currencyCode) -> Decimal {
        guard termCount > 0 else { return 0 }
        var quotient = total / Decimal(termCount)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, CurrencyConverter.minorUnits(for: currencyCode), .plain)
        return rounded
    }
}
