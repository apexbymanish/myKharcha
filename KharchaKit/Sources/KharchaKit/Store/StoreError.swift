public enum StoreError: Error, Equatable {
    case invalidAmount
    case notFound
    case friendHasOpenDebts
    case cannotDeleteFallbackCategory
    case wrongDebtDirection
    case debtAlreadySettled
}
