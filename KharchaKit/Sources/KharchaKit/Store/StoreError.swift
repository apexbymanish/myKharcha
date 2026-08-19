import Foundation

public enum StoreError: Error, Equatable, LocalizedError {
    case invalidAmount
    case notFound
    case friendHasOpenDebts
    case cannotDeleteFallbackCategory
    case wrongDebtDirection
    case debtAlreadySettled

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "That amount isn't valid."
        case .notFound:
            return "I couldn't find that in Kharcha."
        case .friendHasOpenDebts:
            return "That friend still has open debts."
        case .cannotDeleteFallbackCategory:
            return "The Other category can't be deleted."
        case .wrongDebtDirection:
            return "Only money you gave can be written off."
        case .debtAlreadySettled:
            return "That debt is already settled."
        }
    }
}
