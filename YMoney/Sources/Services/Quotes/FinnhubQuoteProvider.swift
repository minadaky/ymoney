import Foundation

/// Finnhub REST API implementation of ``QuoteProvider``.
///
/// Free tier: 60 calls/min, single-symbol `/api/v1/quote` endpoint.
/// Docs: https://finnhub.io/docs/api
struct FinnhubQuoteProvider: QuoteProvider {

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://finnhub.io/api/v1"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - QuoteProvider

    func quote(for symbol: String) async throws -> Quote {
        let url = try buildURL(path: "/quote", queryItems: [
            URLQueryItem(name: "symbol", value: symbol.uppercased())
        ])

        let dto: FinnhubQuoteDTO = try await fetch(url)

        // Finnhub returns all zeros for unknown symbols
        let quote = dto.toQuote(symbol: symbol.uppercased())
        if quote.isEmpty {
            throw QuoteProviderError.invalidSymbol(symbol)
        }
        return quote
    }

    func searchSymbols(query: String) async throws -> [SymbolSearchResult] {
        let url = try buildURL(path: "/search", queryItems: [
            URLQueryItem(name: "q", value: query)
        ])

        let dto: FinnhubSearchDTO = try await fetch(url)
        return dto.result.map { $0.toModel() }
    }

    // MARK: - Networking

    private func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard !apiKey.isEmpty else { throw QuoteProviderError.missingAPIKey }

        var components = URLComponents(string: baseURL + path)!
        var items = queryItems
        items.append(URLQueryItem(name: "token", value: apiKey))
        components.queryItems = items

        guard let url = components.url else {
            throw QuoteProviderError.networkError(
                URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: baseURL + path])
            )
        }
        return url
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)

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

        // Finnhub returns {"error":"..."} for access/auth issues
        if let apiError = try? JSONDecoder().decode(FinnhubErrorDTO.self, from: data),
           !apiError.error.isEmpty {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw QuoteProviderError.apiError(apiError.error, rawResponse: raw)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 data, \(data.count) bytes>"
            throw QuoteProviderError.decodingError(error, rawResponse: raw)
        }
    }
}

// MARK: - Finnhub DTOs (private, maps terse JSON keys)

/// Finnhub error envelope
private struct FinnhubErrorDTO: Decodable {
    let error: String
}

/// Response from `/api/v1/quote`
private struct FinnhubQuoteDTO: Decodable {
    let c: Double   // current price
    let h: Double   // day high
    let l: Double   // day low
    let o: Double   // open
    let pc: Double  // previous close
    let t: Int      // unix timestamp

    func toQuote(symbol: String) -> Quote {
        Quote(
            symbol: symbol,
            currentPrice: c,
            dayHigh: h,
            dayLow: l,
            openPrice: o,
            previousClose: pc,
            timestamp: Date(timeIntervalSince1970: TimeInterval(t))
        )
    }
}

/// Response from `/api/v1/search`
private struct FinnhubSearchDTO: Decodable {
    let count: Int
    let result: [FinnhubSearchResultDTO]
}

private struct FinnhubSearchResultDTO: Decodable {
    let symbol: String
    let description: String
    let type: String
    let displaySymbol: String

    func toModel() -> SymbolSearchResult {
        SymbolSearchResult(
            symbol: symbol,
            description: description,
            type: type,
            displaySymbol: displaySymbol
        )
    }
}
