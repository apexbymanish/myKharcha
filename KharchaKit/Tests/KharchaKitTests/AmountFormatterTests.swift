import Testing
import Foundation
@testable import KharchaKit

@Test func moneyRespectsConfiguredCurrency() {
    // Currency-explicit overload → no shared global mutation, so this stays
    // deterministic under parallel test execution.
    let krw = AmountFormatter.money(12_000, currencyCode: "KRW")
    let usd = AmountFormatter.money(12_000, currencyCode: "USD")

    // Same number, different currency → different rendered strings.
    #expect(krw != usd)
    // Fraction-digit count is currency-defined and locale-independent:
    // KRW has no minor unit, USD has two.
    #expect(!krw.contains(".00"))
    #expect(usd.contains(".00"))
    // Each renders its own currency symbol.
    #expect(krw.contains("₩"))
    #expect(usd.contains("$"))
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
