import Foundation
import os

public enum AmountFormatter {
    // Backing store: an unfair lock keeps the mutable currency code
    // concurrency-safe (Siri handlers format money off the main actor).
    private static let _currencyCode = OSAllocatedUnfairLock(
        initialState: Locale.current.currency?.identifier ?? "USD"
    )

    /// ISO 4217 currency code used when formatting money for display.
    ///
    /// Defaults to the device region's currency so every process (app + Siri
    /// extension) is region-aware out of the box. The app overrides this at
    /// launch from the user's stored preference (Settings → Currency).
    public static var currencyCode: String {
        get { _currencyCode.withLock { $0 } }
        set { _currencyCode.withLock { $0 = newValue } }
    }

    /// Formats `amount` as money in the globally-configured `currencyCode`, using
    /// the current locale for grouping, symbol placement, and the currency's
    /// natural fraction-digit count (e.g. KRW shows none, USD shows two).
    public static func money(_ amount: Decimal) -> String {
        money(amount, currencyCode: currencyCode)
    }

    /// Currency-explicit variant — formats in the given ISO code regardless of
    /// the global preference. Useful where a specific currency must be forced
    /// (and for deterministic tests without mutating global state).
    public static func money(_ amount: Decimal, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode))
    }
}

public extension Decimal {
    /// Siri hands amounts over as Double; round-trip through a 2-dp string so
    /// binary-float artifacts (12.35 → 12.34999…) never reach stored money.
    init(siriDouble: Double) {
        self = Decimal(string: String(format: "%.2f", siriDouble)) ?? Decimal(siriDouble)
        // This rounding pass only does real work on the `?? Decimal(siriDouble)` fallback
        // branch (reached if the %.2f string somehow fails to parse) — that raw
        // Decimal(Double) conversion can carry binary-float noise past 2dp. The
        // `Decimal(string:)` success path above is already exactly 2dp, so rounding
        // it again here is a no-op kept for the shared cleanup below (isZero/-0).
        var rounded = self
        var copy = self
        NSDecimalRound(&rounded, &copy, 2, .plain)
        self = rounded.isZero ? 0 : rounded  // normalize -0
        // Trim trailing zeros by re-parsing a normalized description is unnecessary:
        // Decimal(string: "12000.00") == Decimal(12000) compares equal.
    }
}
