import Foundation

/// Detects an ISO 4217 currency code from free text — a symbol ("$", "₩") or a
/// word ("dollars", "won", "USD"). Used to spot the currency of a pasted amount.
public enum CurrencyDetector {
    private static let symbolCodes: [Character: String] = [
        "$": "USD", "₩": "KRW", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR"
    ]
    private static let wordCodes: [String: String] = [
        "usd": "USD", "dollar": "USD", "dollars": "USD", "buck": "USD", "bucks": "USD",
        "krw": "KRW", "won": "KRW",
        "eur": "EUR", "euro": "EUR", "euros": "EUR",
        "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
        "jpy": "JPY", "yen": "JPY",
        "inr": "INR", "rupee": "INR", "rupees": "INR",
        "npr": "NPR"
    ]

    /// The first currency signalled in `text`, or nil if none is recognised.
    public static func code(in text: String) -> String? {
        for ch in text where symbolCodes[ch] != nil { return symbolCodes[ch] }
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        for word in words where wordCodes[word] != nil { return wordCodes[word] }
        return nil
    }
}

/// Exact `Decimal` currency conversion with correct rounding.
public enum CurrencyConverter {
    /// Convert `amount` (in the source currency) to the target using `rate`
    /// (target units per 1 source unit), rounded to `minorUnits` decimal places.
    public static func convert(_ amount: Decimal, rate: Decimal, minorUnits: Int) -> Decimal {
        var product = amount * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, minorUnits, .plain)
        return rounded
    }

    /// Standard fraction-digit count for a currency (KRW/JPY have none).
    public static func minorUnits(for code: String) -> Int {
        ["KRW", "JPY", "VND", "CLP", "ISK", "KMF", "XOF", "XAF"].contains(code) ? 0 : 2
    }
}

/// Supplies FX rates. Abstracted so KharchaKit stays network-free and testable;
/// the app provides a concrete (Frankfurter-backed) implementation.
public protocol RateProviding: Sendable {
    /// Rate to multiply a `from`-currency amount by to get `to`-currency, for
    /// `date` (nil = latest). Returns nil when unavailable (offline, unknown).
    func rate(from: String, to: String, on date: Date?) async -> Decimal?
}
