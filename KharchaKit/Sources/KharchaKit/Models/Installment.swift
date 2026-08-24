import Foundation
import SwiftData

/// A finite, scheduled obligation: a purchase paid in installments (phone EMI,
/// shop plan) or a loan you took and repay monthly. Unlike `RecurringRule` it has
/// a fixed term and a running balance, and unlike friend `Debt` it isn't tied to a
/// person. Its balance/progress are derived from the `InstallmentPayment` ledger,
/// so the full payment history is always preserved.
@Model
public final class Installment {
    public var id: UUID
    public var name: String
    /// `InstallmentKind` raw value ("purchase" / "loan").
    public var kindRaw: String
    /// The per-month payment (total ÷ term, editable by the user).
    public var monthlyAmount: Decimal
    /// Total number of monthly installments.
    public var termCount: Int
    /// Day of the month the payment is due (1…31, clamped per month).
    public var dayOfMonth: Int
    /// First month the plan is active.
    public var startDate: Date
    /// Category the recorded payment expense is filed under (nil = uncategorized).
    public var categoryID: UUID?
    public var remindDaysBefore: Int
    /// When true, the monthly payment is auto-recorded on the due date.
    public var autoLog: Bool
    /// Loans only: when true, the borrowed cash was recorded as income at creation.
    public var recordPrincipalAsIncome: Bool
    public var note: String?
    /// Explicitly closed (e.g. cancelled or forgiven). Distinct from "fully paid",
    /// which is derived from the ledger.
    public var isClosed: Bool
    public var closedDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: InstallmentKind {
        get { InstallmentKind(rawValue: kindRaw) ?? .purchase }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        name: String,
        kind: InstallmentKind,
        monthlyAmount: Decimal,
        termCount: Int,
        dayOfMonth: Int,
        startDate: Date,
        categoryID: UUID? = nil,
        remindDaysBefore: Int = 3,
        autoLog: Bool = false,
        recordPrincipalAsIncome: Bool = false,
        note: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.monthlyAmount = monthlyAmount
        self.termCount = termCount
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.categoryID = categoryID
        self.remindDaysBefore = remindDaysBefore
        self.autoLog = autoLog
        self.recordPrincipalAsIncome = recordPrincipalAsIncome
        self.note = note
        self.isClosed = false
        self.closedDate = nil
        self.createdAt = .now
        self.updatedAt = .now
    }
}

/// One payment against an installment. Links to the expense `Txn` it created
/// (`txnID`) so deleting the payment can reverse that expense.
@Model
public final class InstallmentPayment {
    public var id: UUID
    public var installmentID: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?
    /// The expense transaction this payment created (nil if none / already removed).
    public var txnID: UUID?
    public var updatedAt: Date

    public init(installmentID: UUID, amount: Decimal, date: Date, note: String? = nil, txnID: UUID? = nil) {
        self.id = UUID()
        self.installmentID = installmentID
        self.amount = amount
        self.date = date
        self.note = note
        self.txnID = txnID
        self.updatedAt = .now
    }
}
