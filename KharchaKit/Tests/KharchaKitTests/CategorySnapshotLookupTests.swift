import Testing
import Foundation
@testable import KharchaKit

struct CategorySnapshotLookupTests {

    private func cat(_ name: String, symbol: String, colorHex: String, isFallback: Bool = false) -> CategorySnapshot {
        CategorySnapshot(id: UUID(), name: name, symbol: symbol, colorHex: colorHex, monthlyBudget: nil, isFallback: isFallback, kind: .expense)
    }

    @Test func resolveFindsExactNameMatch() {
        let food = cat("Food", symbol: "fork.knife", colorHex: "#E07A5F")
        let categories = [food, cat("Transport", symbol: "bus", colorHex: "#3D405B")]

        let resolved = CategorySnapshot.resolve(named: "Food", in: categories)

        #expect(resolved.symbol == "fork.knife")
        #expect(resolved.colorHex == "#E07A5F")
    }

    @Test func resolveFallsBackToFallbackCategoryWhenNameUnmatched() {
        let other = cat("Other", symbol: "tag", colorHex: "#9A9A9A", isFallback: true)
        let categories = [cat("Food", symbol: "fork.knife", colorHex: "#E07A5F"), other]

        // "Deleted Category" no longer exists among current categories.
        let resolved = CategorySnapshot.resolve(named: "Deleted Category", in: categories)

        #expect(resolved.name == "Other")
        #expect(resolved.isFallback == true)
    }

    @Test func resolveUsesHardcodedDefaultWhenNoFallbackCategoryExists() {
        let categories = [cat("Food", symbol: "fork.knife", colorHex: "#E07A5F")]

        let resolved = CategorySnapshot.resolve(named: "Deleted Category", in: categories)

        #expect(resolved.symbol == "tag")
        #expect(resolved.colorHex == "#9A9A9A")
    }
}
