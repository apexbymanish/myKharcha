import Foundation

public struct KharchaBackup: Codable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var categories: [CategoryRecord]
    public var transactions: [TxnRecord]
    public var friends: [FriendRecord]
    public var debts: [DebtRecord]
    public var savingsPots: [SavingsPotRecord]
    public var savingsEntries: [SavingsEntryRecord]
    public var savingsGoals: [SavingsGoalRecord]
    public var installments: [InstallmentRecord]
    public var installmentPayments: [InstallmentPaymentRecord]
    public var recurringRules: [RecurringRuleRecord]

    public struct CategoryRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var colorHex: String
        public var monthlyBudget: Decimal?
        public var isFallback: Bool
        public var kindRaw: String
        public var updatedAt: Date
    }

    public struct TxnRecord: Codable, Sendable {
        public var id: UUID
        public var amount: Decimal
        public var kindRaw: String
        public var categoryID: UUID?
        public var note: String?
        public var date: Date
        public var sourceRaw: String
        public var updatedAt: Date
    }

    public struct FriendRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var phone: String?
        public var photoData: Data?
        public var updatedAt: Date
    }

    public struct DebtRecord: Codable, Sendable {
        public var id: UUID
        public var friendID: UUID?
        public var amount: Decimal
        public var directionRaw: String
        public var date: Date
        public var note: String?
        public var dueDate: Date?
        public var settledAmount: Decimal
        public var settled: Bool
        public var updatedAt: Date
    }

    public struct SavingsPotRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var note: String?
        public var updatedAt: Date
    }

    public struct SavingsEntryRecord: Codable, Sendable {
        public var id: UUID
        public var potID: UUID
        public var amount: Decimal
        public var note: String?
        public var date: Date
        public var updatedAt: Date
    }

    public struct SavingsGoalRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var targetAmount: Decimal
        public var priority: Int
        public var updatedAt: Date
    }

    public struct InstallmentRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var kindRaw: String
        public var monthlyAmount: Decimal
        public var termCount: Int
        public var dayOfMonth: Int
        public var startDate: Date
        public var categoryID: UUID?
        public var remindDaysBefore: Int
        public var autoLog: Bool
        public var recordPrincipalAsIncome: Bool
        public var note: String?
        public var isClosed: Bool
        public var closedDate: Date?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct InstallmentPaymentRecord: Codable, Sendable {
        public var id: UUID
        public var installmentID: UUID
        public var amount: Decimal
        public var date: Date
        public var note: String?
        public var txnID: UUID?
        public var updatedAt: Date
    }

    public struct RecurringRuleRecord: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var amount: Decimal
        public var categoryID: UUID?
        public var dayOfMonth: Int
        public var remindDaysBefore: Int
        public var autoLog: Bool
        public var updatedAt: Date
    }
}
