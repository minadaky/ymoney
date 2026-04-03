import Foundation

/// Central configuration for the quote data source.
///
/// Yahoo Finance is the default provider (no API key required).
/// The JS transform can be overridden at runtime by fetching from a
/// configurable URL, allowing hot-fixes without an app update.
enum QuoteConfiguration {

    private static let jsOverrideKey = "yahooQuoteJSOverride"
    private static let jsOverrideURLKey = "yahooQuoteJSOverrideURL"

    /// A cached JS override stored in UserDefaults (populated from the remote URL).
    static var jsOverride: String? {
        get { UserDefaults.standard.string(forKey: jsOverrideKey) }
        set { UserDefaults.standard.set(newValue, forKey: jsOverrideKey) }
    }

    /// The remote URL to fetch an updated `yahoo_quote_transform.js` from.
    /// Set this in Settings; the app checks on launch.
    static var jsOverrideURL: String? {
        get { UserDefaults.standard.string(forKey: jsOverrideURLKey) }
        set { UserDefaults.standard.set(newValue, forKey: jsOverrideURLKey) }
    }

    /// Build the default ``QuoteProvider`` — Yahoo Finance, no key needed.
    static func makeProvider() -> some QuoteProvider {
        YahooQuoteProvider(jsOverride: jsOverride)
    }

    /// Fetch the latest JS transform from the configured URL and cache it.
    /// Call this on app launch. Fails silently — the bundled JS is always the fallback.
    static func refreshJSOverride() async {
        guard let urlString = jsOverrideURL,
              !urlString.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: urlString),
              url.scheme == "https" else { return }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("YMoney/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let script = String(data: data, encoding: .utf8),
                  script.contains("transformQuote") else { return }

            jsOverride = script
        } catch {
            // Silent fail — keep using cached or bundled JS
        }
    }

    /// Clear the cached override, reverting to the bundled JS.
    static func clearOverride() {
        jsOverride = nil
    }
}
