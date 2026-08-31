import Foundation

extension CategorySnapshot {
    /// A gray/tag category to use when neither a matching name nor a
    /// fallback ("Other") category can be found — should only happen for
    /// data that predates category seeding.
    private static let hardcodedDefault = CategorySnapshot(
        id: UUID(), name: "Other", symbol: "tag", colorHex: "#9A9A9A",
        monthlyBudget: nil, isFallback: true, kind: .any
    )

    /// Looks up the category matching `name` (e.g. a transaction's
    /// `categoryName`) so its icon/color can be rendered. Falls back to the
    /// list's own fallback ("Other") category when the name no longer
    /// matches any current category (renamed/deleted), then to a
    /// hardcoded default if even that is missing.
    public static func resolve(named name: String, in categories: [CategorySnapshot]) -> CategorySnapshot {
        categories.first(where: { $0.name == name })
            ?? categories.first(where: \.isFallback)
            ?? hardcodedDefault
    }
}
