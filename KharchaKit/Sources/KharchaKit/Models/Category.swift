import Foundation
import SwiftData

/// Which transaction kind(s) a category applies to, so the Add screen shows only
/// relevant categories: `.expense` under Expense, `.income` under Income, `.any`
/// (e.g. the "Other" fallback) under both.
public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    case expense, income, any

    /// True when this category should be offered while logging `txnKind`.
    public func applies(to txnKind: TxnKind) -> Bool {
        switch self {
        case .any: return true
        case .expense: return txnKind == .expense
        case .income: return txnKind == .income
        }
    }
}

@Model
public final class Category {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorHex: String
    public var monthlyBudget: Decimal?
    public var isFallback: Bool
    /// `CategoryKind` raw value. Defaults to "expense" so existing stored categories
    /// migrate as expense categories (lightweight, additive migration).
    public var kindRaw: String = CategoryKind.expense.rawValue
    public var updatedAt: Date

    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?, isFallback: Bool = false, kind: CategoryKind = .expense) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
        self.isFallback = isFallback
        self.kindRaw = kind.rawValue
        self.updatedAt = .now
    }
}
