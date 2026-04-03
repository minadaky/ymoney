import Testing
import Foundation
import JavaScriptCore

/// Tests the `yahoo_quote_transform.js` JavaScript adapter against real
/// Yahoo Finance v8/chart responses captured from each exchange type.
///
/// Fixture files live in `Fixtures/` and were fetched from production Yahoo.
/// The JS file under test is the bundled `yahoo_quote_transform.js`.
struct YahooQuoteTransformTests {

    // MARK: - Test cases

    struct TestExpectation {
        let file: String          // fixture filename (without .json)
        let symbol: String        // expected symbol in output
        let category: String      // for display: "NYSE", "NASDAQ", etc.
        let minPrice: Double      // sanity lower bound (0 for money market)
        let allowZeroDayHL: Bool  // mutual funds may lack day high/low
    }

    static let expectations: [TestExpectation] = [
        // NYSE equities
        .init(file: "yahoo_JPM",     symbol: "JPM",     category: "NYSE",        minPrice: 100, allowZeroDayHL: false),
        .init(file: "yahoo_GE",      symbol: "GE",      category: "NYSE",        minPrice: 50,  allowZeroDayHL: false),
        .init(file: "yahoo_WMT",     symbol: "WMT",     category: "NASDAQ(GS)",  minPrice: 50,  allowZeroDayHL: false),

        // NASDAQ equities
        .init(file: "yahoo_AAPL",    symbol: "AAPL",    category: "NASDAQ",      minPrice: 100, allowZeroDayHL: false),
        .init(file: "yahoo_MSFT",    symbol: "MSFT",    category: "NASDAQ",      minPrice: 200, allowZeroDayHL: false),
        .init(file: "yahoo_TSLA",    symbol: "TSLA",    category: "NASDAQ",      minPrice: 50,  allowZeroDayHL: false),

        // AMEX / NYSE Arca equities/ETFs used as AMEX-ish
        .init(file: "yahoo_SPDW",    symbol: "SPDW",    category: "AMEX/Arca",   minPrice: 10,  allowZeroDayHL: false),
        .init(file: "yahoo_GNR",     symbol: "GNR",     category: "AMEX/Arca",   minPrice: 10,  allowZeroDayHL: false),
        .init(file: "yahoo_PRFZ",    symbol: "PRFZ",    category: "AMEX/Arca",   minPrice: 10,  allowZeroDayHL: false),

        // US Mutual Funds
        .init(file: "yahoo_VMFXX",   symbol: "VMFXX",   category: "MutualFund",  minPrice: 0.5, allowZeroDayHL: true),
        .init(file: "yahoo_VTSAX",   symbol: "VTSAX",   category: "MutualFund",  minPrice: 50,  allowZeroDayHL: true),
        .init(file: "yahoo_FXAIX",   symbol: "FXAIX",   category: "MutualFund",  minPrice: 50,  allowZeroDayHL: true),

        // US ETFs
        .init(file: "yahoo_SPY",     symbol: "SPY",     category: "ETF",         minPrice: 200, allowZeroDayHL: false),
        .init(file: "yahoo_QQQ",     symbol: "QQQ",     category: "ETF",         minPrice: 200, allowZeroDayHL: false),
        .init(file: "yahoo_VTI",     symbol: "VTI",     category: "ETF",         minPrice: 100, allowZeroDayHL: false),

        // European equity (Nestlé, SIX Swiss Exchange)
        .init(file: "yahoo_NESN_SW", symbol: "NESN.SW", category: "Europe/SIX",  minPrice: 30,  allowZeroDayHL: false),

        // Japanese equity (Toyota, Tokyo Stock Exchange)
        .init(file: "yahoo_7203_T",  symbol: "7203.T",  category: "Japan/TSE",   minPrice: 1000, allowZeroDayHL: false),
    ]

    // MARK: - JS engine setup

    private static func loadJS() -> String {
        let jsPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("yahoo_quote_transform.js")
        return (try? String(contentsOf: jsPath)) ?? ""
    }

    private static func loadFixture(_ name: String) -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        return (try? String(contentsOf: path)) ?? ""
    }

    private static func transform(jsSource: String, rawJSON: String, symbol: String) -> (result: [String: Any]?, error: String?) {
        let ctx = JSContext()!
        ctx.evaluateScript(jsSource)

        guard let fn = ctx.objectForKeyedSubscript("transformQuote"),
              !fn.isUndefined,
              let resultValue = fn.call(withArguments: [rawJSON, symbol]),
              let resultString = resultValue.toString(),
              let data = resultString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "JS execution failed")
        }

        if let err = dict["error"] as? String {
            return (nil, err)
        }
        return (dict, nil)
    }

    // MARK: - Tests

    @Test("All fixtures parse without error", arguments: expectations)
    func fixtureParses(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        #expect(!js.isEmpty, "JS source should load")

        let raw = Self.loadFixture(expectation.file)
        #expect(!raw.isEmpty, "Fixture \(expectation.file) should load")

        let (result, error) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)
        #expect(error == nil, "[\(expectation.category)] \(expectation.symbol): \(error ?? "")")
        #expect(result != nil, "[\(expectation.category)] \(expectation.symbol): result should not be nil")
    }

    @Test("Symbol matches", arguments: expectations)
    func symbolMatches(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        let raw = Self.loadFixture(expectation.file)
        let (result, _) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)

        let symbol = result?["symbol"] as? String ?? ""
        #expect(symbol == expectation.symbol,
                "[\(expectation.category)] Expected \(expectation.symbol), got \(symbol)")
    }

    @Test("Current price above minimum", arguments: expectations)
    func priceAboveMinimum(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        let raw = Self.loadFixture(expectation.file)
        let (result, _) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)

        let price = result?["currentPrice"] as? Double ?? 0
        #expect(price >= expectation.minPrice,
                "[\(expectation.category)] \(expectation.symbol): price \(price) < min \(expectation.minPrice)")
    }

    @Test("Previous close is non-zero", arguments: expectations)
    func previousCloseNonZero(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        let raw = Self.loadFixture(expectation.file)
        let (result, _) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)

        let prevClose = result?["previousClose"] as? Double ?? 0
        #expect(prevClose > 0,
                "[\(expectation.category)] \(expectation.symbol): previousClose should be > 0, got \(prevClose)")
    }

    @Test("Timestamp is reasonable", arguments: expectations)
    func timestampReasonable(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        let raw = Self.loadFixture(expectation.file)
        let (result, _) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)

        let ts = result?["timestamp"] as? Double ?? 0
        // Should be after 2020-01-01 (1577836800) and before 2030-01-01 (1893456000)
        #expect(ts > 1_577_836_800 && ts < 1_893_456_000,
                "[\(expectation.category)] \(expectation.symbol): timestamp \(ts) out of range")
    }

    @Test("Day high/low present for equities and ETFs", arguments: expectations.filter { !$0.allowZeroDayHL })
    func dayHighLowPresent(expectation: TestExpectation) throws {
        let js = Self.loadJS()
        let raw = Self.loadFixture(expectation.file)
        let (result, _) = Self.transform(jsSource: js, rawJSON: raw, symbol: expectation.symbol)

        let high = result?["dayHigh"] as? Double ?? 0
        let low = result?["dayLow"] as? Double ?? 0
        #expect(high > 0, "[\(expectation.category)] \(expectation.symbol): dayHigh should be > 0")
        #expect(low > 0, "[\(expectation.category)] \(expectation.symbol): dayLow should be > 0")
        #expect(high >= low, "[\(expectation.category)] \(expectation.symbol): dayHigh should >= dayLow")
    }

    @Test("Error response handled gracefully")
    func errorResponseHandled() {
        let js = Self.loadJS()
        let errorJSON = """
        {"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}
        """
        let (result, error) = Self.transform(jsSource: js, rawJSON: errorJSON, symbol: "INVALID")
        #expect(error != nil, "Should return an error for null results")
        #expect(result == nil || result?["error"] != nil)
    }

    @Test("Malformed JSON handled gracefully")
    func malformedJSONHandled() {
        let js = Self.loadJS()
        let (_, error) = Self.transform(jsSource: js, rawJSON: "not json at all", symbol: "X")
        // The JS JSON.parse will throw — JSContext returns undefined
        #expect(error != nil, "Should fail gracefully on malformed input")
    }
}

// MARK: - Equatable conformance for parameterized tests
extension YahooQuoteTransformTests.TestExpectation: Sendable, CustomTestStringConvertible {
    var testDescription: String { "\(category)/\(symbol)" }
}
