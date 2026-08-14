import Foundation
import SwiftData

@Model
public final class Category {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorHex: String
    public var monthlyBudget: Decimal?
    public var isFallback: Bool
    public var updatedAt: Date

    public init(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?, isFallback: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
        self.isFallback = isFallback
        self.updatedAt = .now
    }
}
