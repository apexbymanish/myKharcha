import Foundation
import SwiftData

/// A named savings pot — typically a bank ("Anonymous Bank"). Its balance is
/// derived from its `SavingsEntry` ledger, so the full history of what you saved
/// is always preserved.
@Model
public final class SavingsPot {
    public var id: UUID
    public var name: String
    public var note: String?
    public var updatedAt: Date

    public init(name: String, note: String? = nil) {
        self.id = UUID()
        self.name = name
        self.note = note
        self.updatedAt = .now
    }
}

/// One record in a pot's ledger: a deposit (positive amount) or withdrawal
/// (negative amount), with a date and optional note ("Salary → savings").
@Model
public final class SavingsEntry {
    public var id: UUID
    public var potID: UUID
    public var amount: Decimal
    public var note: String?
    public var date: Date
    public var updatedAt: Date

    public init(potID: UUID, amount: Decimal, note: String?, date: Date) {
        self.id = UUID()
        self.potID = potID
        self.amount = amount
        self.note = note
        self.date = date
        self.updatedAt = .now
    }
}

/// A savings envelope/goal the pot should cover (e.g. "Emergency", "Trip").
/// `priority` orders reserves; lower reserves first.
@Model
public final class SavingsGoal {
    public var id: UUID
    public var name: String
    public var targetAmount: Decimal
    public var priority: Int
    public var updatedAt: Date

    public init(name: String, targetAmount: Decimal, priority: Int = 0) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.priority = priority
        self.updatedAt = .now
    }
}
