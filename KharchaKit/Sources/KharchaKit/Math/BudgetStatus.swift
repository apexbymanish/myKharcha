import Foundation

public struct BudgetStatus: Sendable, Equatable {
    public let categoryID: UUID
    public let categoryName: String
    public let spent: Decimal
    public let budget: Decimal
    public var isOver: Bool { spent > budget }

    public init(categoryID: UUID, categoryName: String, spent: Decimal, budget: Decimal) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.spent = spent
        self.budget = budget
    }
}
