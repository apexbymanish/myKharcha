import Foundation

public struct CategorySpend: Sendable, Equatable {
    public let categoryID: UUID?
    public let categoryName: String
    public let amount: Decimal

    public init(categoryID: UUID?, categoryName: String, amount: Decimal) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.amount = amount
    }
}

public struct SpendingBreakdown: Sendable, Equatable {
    public let total: Decimal
    public let categories: [CategorySpend]

    public init(total: Decimal, categories: [CategorySpend]) {
        self.total = total
        self.categories = categories
    }
}
