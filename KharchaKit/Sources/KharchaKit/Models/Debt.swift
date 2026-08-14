import Foundation
import SwiftData

public enum DebtDirection: String, Codable, Sendable { case iGave, iTook }

@Model
public final class Debt {
    public var id: UUID
    public var friend: Friend?
    public var amount: Decimal
    public var directionRaw: String
    public var date: Date
    public var note: String?
    public var dueDate: Date?
    public var settledAmount: Decimal
    public var settled: Bool
    public var updatedAt: Date

    public var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .iGave }
        set { directionRaw = newValue.rawValue }
    }
    public var remaining: Decimal { amount - settledAmount }

    public init(friend: Friend?, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?) {
        self.id = UUID()
        self.friend = friend
        self.amount = amount
        self.directionRaw = direction.rawValue
        self.date = date
        self.note = note
        self.dueDate = dueDate
        self.settledAmount = 0
        self.settled = false
        self.updatedAt = .now
    }
}
