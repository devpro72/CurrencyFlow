import Foundation

/// Fetches live exchange rates from free providers, with fallbacks,
/// plus a persistent on-disk cache for offline launches.
enum RatesService {

    enum FetchError: LocalizedError {
        case noProviderAvailable

        var errorDescription: String? {
            switch self {
            case .noProviderAvailable:
                return "No rate provider could be reached."
            }
        }
    }

    // MARK: Networking

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: Public API

    static func fetch() async throws -> RateSnapshot {
        var lastError: Error?
        for provider in providers {
            do {
                return try await provider()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FetchError.noProviderAvailable
    }

    // MARK: Providers

    private static let providers: [() async throws -> RateSnapshot] = [
        fetchExchangeRateAPI,
        fetchJsDelivrAPI,
        fetchFrankfurter,
    ]

    /// Primary: open.er-api.com — free, no key, ~160 currencies.
    private static func fetchExchangeRateAPI() async throws -> RateSnapshot {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            throw FetchError.noProviderAvailable
        }
        let (data, _) = try await session.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.noProviderAvailable
        }
        guard root["result"] as? String == "success" else {
            throw FetchError.noProviderAvailable
        }
        guard let rates = decodeRates(root["rates"]) else {
            throw FetchError.noProviderAvailable
        }
        guard rates.count >= 40 else {
            throw FetchError.noProviderAvailable
        }
        var updated = Date()
        if let unix = root["time_last_update_unix"] as? Double {
            updated = Date(timeIntervalSince1970: unix)
        }
        return RateSnapshot(
            rates: rates,
            updated: updated,
            provider: "ExchangeRate-API · open.er-api.com"
        )
    }

    /// Fallback 1: fawazahmed0/currency-api via jsDelivr CDN — free, no key, ~200 currencies.
    private static func fetchJsDelivrAPI() async throws -> RateSnapshot {
        guard let url = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json") else {
            throw FetchError.noProviderAvailable
        }
        let (data, _) = try await session.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawUSD = root["usd"] as? [String: Any],
              let rates = decodeRates(rawUSD, keysAreLowercased: true),
              rates.count >= 40 else {
            throw FetchError.noProviderAvailable
        }
        return RateSnapshot(
            rates: rates,
            updated: Date(),
            provider: "Currency-API · jsDelivr CDN"
        )
    }

    /// Fallback 2: Frankfurter (European Central Bank) — ~30 currencies.
    private static func fetchFrankfurter() async throws -> RateSnapshot {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else {
            throw FetchError.noProviderAvailable
        }
        let (data, _) = try await session.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var rates = decodeRates(root["rates"]) else {
            throw FetchError.noProviderAvailable
        }
        rates["USD"] = 1
        let updated = root["date"] as? String ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: updated) ?? Date()
        return RateSnapshot(rates: rates, updated: date, provider: "Frankfurter · ECB")
    }

    // MARK: Decoding

    private static func decodeRates(_ any: Any?, keysAreLowercased: Bool = false) -> [String: Double]? {
        guard let raw = any as? [String: Any] else { return nil }
        var result: [String: Double] = [:]
        for (key, value) in raw {
            let code = (keysAreLowercased ? key.uppercased() : key)
            guard code.count == 3, code.allSatisfy({ $0.isLetter }) else { continue }
            guard let number = value as? Double, number.isFinite, number > 0 else {
                if let number = value as? Int, Double(number) > 0 {
                    result[code] = Double(number)
                }
                continue
            }
            result[code] = number
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Disk cache

    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CurrencyFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var cacheURL: URL {
        supportDirectory().appendingPathComponent("rates-cache.json")
    }

    static var recordsURL: URL {
        supportDirectory().appendingPathComponent("saved-conversions.json")
    }

    static func loadCache() -> RateSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(RateSnapshot.self, from: data)
    }

    static func saveCache(_ snapshot: RateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
