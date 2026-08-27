import Foundation
import KharchaKit

/// App-side currency preference, stored in the shared App Group defaults so both
/// the app and the Siri extension resolve the same currency. The value is an
/// ISO 4217 code (e.g. "USD", "KRW"); an absent value means "use the region
/// default" that `AmountFormatter.currencyCode` already resolves at launch.
enum CurrencyPreference {
    static let defaultsKey = "currencyCode"

    /// A curated shortlist of common currencies, always including the device's
    /// current currency so the picker can represent the default selection.
    static var options: [String] {
        var codes = [
            "USD", "EUR", "GBP", "JPY", "KRW", "INR", "NPR",
            "CNY", "AUD", "CAD", "CHF", "SGD", "HKD", "AED", "THB"
        ]
        if let current = Locale.current.currency?.identifier, !codes.contains(current) {
            codes.insert(current, at: 0)
        }
        return codes
    }

    /// "USD — US Dollar" style label, localized to the user's language.
    static func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) — \(name)"
    }
}
