import Foundation
import SwiftData

public enum TxnKind: String, Codable, Sendable { case expense, income }
public enum TxnSource: String, Codable, Sendable { case manual, siri }

@Model
public final class Txn {
    public var id: UUID
    public var amount: Decimal
    public var kindRaw: String
    public var category: Category?
    public var note: String?
    public var date: Date
    public var sourceRaw: String
    public var updatedAt: Date

    public var kind: TxnKind {
        get { TxnKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
    public var source: TxnSource {
        get { TxnSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public init(amount: Decimal, kind: TxnKind, category: Category?, note: String?, date: Date, source: TxnSource) {
        self.id = UUID()
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.category = category
        self.note = note
        self.date = date
        self.sourceRaw = source.rawValue
        self.updatedAt = .now
    }
}
