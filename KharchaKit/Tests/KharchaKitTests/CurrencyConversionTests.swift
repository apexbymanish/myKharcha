import Testing
import Foundation
@testable import KharchaKit

@Test func detectsCurrencyFromSymbolsAndWords() {
    #expect(CurrencyDetector.code(in: "$10 lunch") == "USD")
    #expect(CurrencyDetector.code(in: "₩13,000 taxi") == "KRW")
    #expect(CurrencyDetector.code(in: "paid 10 dollars") == "USD")
    #expect(CurrencyDetector.code(in: "5000 won") == "KRW")
    #expect(CurrencyDetector.code(in: "€20 book") == "EUR")
    #expect(CurrencyDetector.code(in: "1200 for food") == nil)
}

@Test func convertsWithRoundingToMinorUnits() {
    // KRW has no minor units → rounds to whole won.
    #expect(CurrencyConverter.convert(10, rate: Decimal(string: "1330.5")!, minorUnits: 0) == 13305)
    #expect(CurrencyConverter.convert(10, rate: Decimal(string: "1330.55")!, minorUnits: 0) == 13306) // 13305.5 rounds up
    // USD-style two-dp.
    #expect(CurrencyConverter.convert(Decimal(string: "13305")!, rate: Decimal(string: "0.00075")!, minorUnits: 2) == Decimal(string: "9.98")!)
    #expect(CurrencyConverter.minorUnits(for: "KRW") == 0)
    #expect(CurrencyConverter.minorUnits(for: "USD") == 2)
}

private struct StubRates: RateProviding {
    let value: Decimal
    func rate(from: String, to: String, on date: Date?) async -> Decimal? { value }
}

@Test @MainActor func importConvertsForeignAmountToBase() async throws {
    let store = try makeStore()
    let vm = ImportViewModel(store: store, rates: StubRates(value: 1300))
    await vm.parse("$10 lunch", now: d(2026, 8, 1), allowModel: false, baseCurrency: "KRW")

    #expect(vm.state.rows.count == 1)
    let row = vm.state.rows[0]
    #expect(row.originalCurrency == "USD")
    #expect(row.originalAmount == 10)
    #expect(row.amount == 13_000)  // 10 × 1300, KRW rounded to whole won
}

@Test @MainActor func importLeavesBaseCurrencyAmountUnconverted() async throws {
    let store = try makeStore()
    let vm = ImportViewModel(store: store, rates: StubRates(value: 1300))
    await vm.parse("₩5000 taxi", now: d(2026, 8, 1), allowModel: false, baseCurrency: "KRW")

    #expect(vm.state.rows.count == 1)
    let row = vm.state.rows[0]
    #expect(row.originalCurrency == nil)  // already base → no conversion
    #expect(row.amount == 5000)
}
