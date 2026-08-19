import Testing
import Foundation
@testable import KharchaKit

@Test func krwFormatsGroupedWithoutTrailingZeros() {
    #expect(AmountFormatter.krw(12_000) == "₩12,000")
    #expect(AmountFormatter.krw(Decimal(string: "12000.5")!) == "₩12,000.5")
    #expect(AmountFormatter.krw(0) == "₩0")
    #expect(AmountFormatter.krw(3_000_000) == "₩3,000,000")
}

@Test func siriDoubleConversionIsExactToTwoPlaces() {
    #expect(Decimal(siriDouble: 12.35) == Decimal(string: "12.35")!)
    #expect(Decimal(siriDouble: 12000) == Decimal(12000))
    #expect(Decimal(siriDouble: 0.1 + 0.2) == Decimal(string: "0.3")!)
}

@Test func storeErrorsHaveSpokenDescriptions() {
    for error: StoreError in [.invalidAmount, .notFound, .friendHasOpenDebts, .cannotDeleteFallbackCategory, .wrongDebtDirection, .debtAlreadySettled, .containerUnavailable, .invalidDayOfMonth] {
        #expect(!(error.errorDescription ?? "").isEmpty)
    }
    #expect(StoreError.debtAlreadySettled.errorDescription == "That debt is already settled.")
    #expect(StoreError.containerUnavailable.errorDescription == "Couldn't open your data — open Kharcha once.")
    #expect(StoreError.invalidDayOfMonth.errorDescription == "That day of the month isn't valid.")
}
