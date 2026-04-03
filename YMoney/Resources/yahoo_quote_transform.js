// yahoo_quote_transform.js
// ----------------------------------------------------------
// JavaScript adapter between raw Yahoo Finance v8/chart JSON
// and the normalised quote shape the app expects.
//
// This file is evaluated inside JavaScriptCore on-device.
// It can be hot-swapped (e.g. via remote config or UserDefaults)
// without shipping a new app binary if Yahoo changes their format.
// ----------------------------------------------------------

/**
 * Transform a raw Yahoo Finance v8/finance/chart response into
 * a normalised quote object.
 *
 * @param {string} rawJSON  – The full JSON body from Yahoo.
 * @param {string} symbol   – The requested ticker symbol.
 * @returns {string}        – JSON string of the normalised quote.
 */
function transformQuote(rawJSON, symbol) {
    var data = JSON.parse(rawJSON);

    // Drill into the response envelope
    var chart = data.chart || {};
    var results = chart.result;
    if (!results || results.length === 0) {
        var errMsg = (chart.error && chart.error.description) || "No data returned";
        return JSON.stringify({ error: errMsg });
    }

    var result = results[0];
    var meta = result.meta || {};

    // Prefer meta-level fields (always present), fall back to
    // the indicators array for OHLC when meta is sparse.
    var indicators = (result.indicators && result.indicators.quote
                      && result.indicators.quote[0]) || {};

    var lastClose  = _last(indicators.close);
    var lastHigh   = _last(indicators.high);
    var lastLow    = _last(indicators.low);
    var lastOpen   = _last(indicators.open);

    var currentPrice = meta.regularMarketPrice || lastClose || 0;
    var dayHigh      = meta.regularMarketDayHigh || lastHigh || 0;
    var dayLow       = meta.regularMarketDayLow  || lastLow  || 0;
    var openPrice    = meta.regularMarketOpen     || lastOpen || 0;
    var prevClose    = meta.chartPreviousClose
                    || meta.previousClose
                    || currentPrice
                    || 0;
    var timestamp    = meta.regularMarketTime || 0;
    var name         = meta.longName || meta.shortName || symbol;

    return JSON.stringify({
        symbol:        meta.symbol || symbol,
        name:          name,
        currentPrice:  currentPrice,
        dayHigh:       dayHigh,
        dayLow:        dayLow,
        openPrice:     openPrice,
        previousClose: prevClose,
        timestamp:     timestamp
    });
}

/** Return the last non-null element of an array, or null. */
function _last(arr) {
    if (!arr || arr.length === 0) return null;
    for (var i = arr.length - 1; i >= 0; i--) {
        if (arr[i] !== null && arr[i] !== undefined) return arr[i];
    }
    return null;
}
