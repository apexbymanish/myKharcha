import Foundation

public struct RecurringRuleSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let amount: Decimal
    public let categoryName: String
    public let dayOfMonth: Int
    public let remindDaysBefore: Int
    public let autoLog: Bool

    public init(id: UUID, name: String, amount: Decimal, categoryName: String, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryName = categoryName
        self.dayOfMonth = dayOfMonth
        self.remindDaysBefore = remindDaysBefore
        self.autoLog = autoLog
    }
}
