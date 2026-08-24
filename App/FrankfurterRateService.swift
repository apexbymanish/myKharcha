import Foundation
import KharchaKit

/// `RateProviding` backed by Frankfurter (https://frankfurter.dev) — free, no API
/// key, ECB reference rates. Fetches `GET /v1/{date|latest}?base=…&symbols=…`,
/// caches the result in the shared App Group defaults, and falls back to the last
/// cached rate when offline.
struct FrankfurterRateService: RateProviding {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard
    }
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct Response: Decodable { let rates: [String: Decimal] }

    func rate(from: String, to: String, on date: Date?) async -> Decimal? {
        guard from != to else { return 1 }
        let path = date.map { Self.dateFormatter.string(from: $0) } ?? "latest"
        let cacheKey = "fx.\(path).\(from).\(to)"

        var components = URLComponents(string: "https://api.frankfurter.dev/v1/\(path)")
        components?.queryItems = [
            URLQueryItem(name: "base", value: from),
            URLQueryItem(name: "symbols", value: to)
        ]
        guard let url = components?.url else { return cachedRate(cacheKey) }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if let rate = decoded.rates[to] {
                Self.defaults.set("\(rate)", forKey: cacheKey)
                return rate
            }
            return cachedRate(cacheKey)
        } catch {
            return cachedRate(cacheKey) // offline → last known rate
        }
    }

    private func cachedRate(_ key: String) -> Decimal? {
        Self.defaults.string(forKey: key).flatMap { Decimal(string: $0) }
    }
}
