import Foundation

// MARK: - Quote Model (App-owned, provider-agnostic)

/// A normalized stock quote independent of any API provider's schema.
struct Quote: Sendable {
    let symbol: String
    let currentPrice: Double
    let dayHigh: Double
    let dayLow: Double
    let openPrice: Double
    let previousClose: Double
    let timestamp: Date

    /// Daily price change (current − previous close).
    var change: Double { currentPrice - previousClose }

    /// Daily change as a percentage.
    var changePercent: Double {
        guard previousClose != 0 else { return 0 }
        return (change / previousClose) * 100
    }

    /// `true` when the API returned all-zero prices (invalid symbol on Finnhub).
    var isEmpty: Bool {
        currentPrice == 0 && dayHigh == 0 && dayLow == 0 && openPrice == 0 && previousClose == 0
    }
}

// MARK: - Symbol Search Result

struct SymbolSearchResult: Sendable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let description: String
    let type: String
    let displaySymbol: String
}

// MARK: - Provider Errors

enum QuoteProviderError: LocalizedError {
    case invalidSymbol(String)
    case rateLimited
    case networkError(Error)
    case decodingError(Error, rawResponse: String)
    case apiError(String, rawResponse: String)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidSymbol(let s): return "Invalid or unknown symbol: \(s)"
        case .rateLimited:          return "Rate limit exceeded — try again shortly"
        case .networkError(let e):  return "Network error: \(e.localizedDescription)"
        case .decodingError(let e, _): return "Failed to parse response: \(e.localizedDescription)"
        case .apiError(let msg, _): return "Finnhub: \(msg)"
        case .missingAPIKey:        return "Finnhub API key not configured — add it in Settings"
        }
    }

    /// Full diagnostic string including raw API response when available.
    var diagnosticDescription: String {
        switch self {
        case .decodingError(let e, let raw):
            return "Decoding error: \(e.localizedDescription)\n\nRaw response:\n\(raw)"
        case .apiError(let msg, let raw):
            return "API error: \(msg)\n\nRaw response:\n\(raw)"
        default:
            return errorDescription ?? "Unknown error"
        }
    }
}

// MARK: - Provider Protocol

/// Abstraction over any stock-quote data source.
protocol QuoteProvider: Sendable {
    /// Fetch a single real-time quote.
    func quote(for symbol: String) async throws -> Quote

    /// Search for symbols matching a query string.
    func searchSymbols(query: String) async throws -> [SymbolSearchResult]
}
