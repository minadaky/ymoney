import Foundation
import JavaScriptCore

/// Yahoo Finance v8/chart implementation of ``QuoteProvider``.
///
/// Uses the unofficial but currently-working endpoint:
///   `query1.finance.yahoo.com/v8/finance/chart/{symbol}`
///
/// Raw JSON is passed through a JavaScript transformation layer
/// (`yahoo_quote_transform.js`) so format changes can be fixed
/// without recompiling the app.
struct YahooQuoteProvider: QuoteProvider {

    private let session: URLSession
    private let jsSource: String

    /// Initialise with an optional custom JS source.
    /// If `nil`, the bundled `yahoo_quote_transform.js` is loaded.
    init(session: URLSession = .shared, jsOverride: String? = nil) {
        self.session = session

        if let override = jsOverride {
            self.jsSource = override
        } else if let url = Bundle.main.url(forResource: "yahoo_quote_transform", withExtension: "js"),
                  let src = try? String(contentsOf: url) {
            self.jsSource = src
        } else {
            // Fallback: should never happen in a correctly-built app
            self.jsSource = ""
        }
    }

    // MARK: - QuoteProvider

    func quote(for symbol: String) async throws -> Quote {
        let upper = symbol.uppercased()
        let url = try buildURL(symbol: upper)
        let rawJSON = try await fetchRaw(url)
        return try transform(rawJSON: rawJSON, symbol: upper)
    }

    func searchSymbols(query: String) async throws -> [SymbolSearchResult] {
        // Yahoo v8/chart doesn't have a search endpoint.
        // Return empty — symbol search can be added later via a
        // different Yahoo endpoint or kept on Finnhub.
        return []
    }

    // MARK: - Networking

    private func buildURL(symbol: String) throws -> URL {
        let str = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        guard let url = URL(string: str) else {
            throw QuoteProviderError.networkError(URLError(.badURL))
        }
        return url
    }

    private func fetchRaw(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QuoteProviderError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw QuoteProviderError.rateLimited
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Non-UTF8 response"]),
                rawResponse: "<\(data.count) bytes>"
            )
        }
        return json
    }

    // MARK: - JavaScript Transformation

    private func transform(rawJSON: String, symbol: String) throws -> Quote {
        guard !jsSource.isEmpty else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "JS transform script not loaded"]),
                rawResponse: rawJSON
            )
        }

        guard let ctx = JSContext() else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create JavaScript context"]),
                rawResponse: rawJSON
            )
        }
        ctx.evaluateScript(jsSource)

        guard let fn = ctx.objectForKeyedSubscript("transformQuote"),
              !fn.isUndefined else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "transformQuote function not found in JS"]),
                rawResponse: rawJSON
            )
        }

        guard let resultValue = fn.call(withArguments: [rawJSON, symbol]),
              let resultString = resultValue.toString() else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "JS transform returned nil"]),
                rawResponse: rawJSON
            )
        }

        guard let resultData = resultString.data(using: .utf8) else {
            throw QuoteProviderError.decodingError(
                NSError(domain: "YahooQuoteProvider", code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "JS result not valid UTF-8"]),
                rawResponse: rawJSON
            )
        }

        let dto: YahooTransformResult
        do {
            dto = try JSONDecoder().decode(YahooTransformResult.self, from: resultData)
        } catch {
            throw QuoteProviderError.decodingError(error, rawResponse: resultString)
        }

        if let err = dto.error {
            throw QuoteProviderError.apiError(err, rawResponse: rawJSON)
        }

        let quote = Quote(
            symbol: dto.symbol ?? symbol,
            currentPrice: dto.currentPrice ?? 0,
            dayHigh: dto.dayHigh ?? 0,
            dayLow: dto.dayLow ?? 0,
            openPrice: dto.openPrice ?? 0,
            previousClose: dto.previousClose ?? 0,
            timestamp: Date(timeIntervalSince1970: TimeInterval(dto.timestamp ?? 0))
        )

        if quote.isEmpty {
            throw QuoteProviderError.invalidSymbol(symbol)
        }

        return quote
    }
}

// MARK: - JS→Swift bridge DTO

private struct YahooTransformResult: Decodable {
    let symbol: String?
    let name: String?
    let currentPrice: Double?
    let dayHigh: Double?
    let dayLow: Double?
    let openPrice: Double?
    let previousClose: Double?
    let timestamp: Int?
    let error: String?
}
