import Foundation

public enum AmountFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    public static func krw(_ amount: Decimal) -> String {
        "₩" + (formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")
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
