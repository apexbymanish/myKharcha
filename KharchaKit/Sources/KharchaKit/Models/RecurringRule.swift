import Foundation
import SwiftData

@Model
public final class RecurringRule {
    public var id: UUID
    public var name: String
    public var amount: Decimal
    public var category: Category?
    public var dayOfMonth: Int
    public var remindDaysBefore: Int
    public var autoLog: Bool
    public var updatedAt: Date

    public init(name: String, amount: Decimal, category: Category?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.category = category
        self.dayOfMonth = dayOfMonth
        self.remindDaysBefore = remindDaysBefore
        self.autoLog = autoLog
        self.updatedAt = .now
    }
}
