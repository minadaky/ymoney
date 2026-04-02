import Foundation

/// Currency formatting utilities
enum CurrencyFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f
    }()

    private static let compactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        f.maximumFractionDigits = 0
        return f
    }()

    /// Format a Decimal as currency string (e.g., "$1,234.56")
    static func format(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "$0.00" }
        return formatter.string(from: amount) ?? "$0.00"
    }

    /// Format a Double as currency string
    static func format(_ amount: Double) -> String {
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// Format with compact notation for large values
    static func formatCompact(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "$0" }
        let doubleVal = amount.doubleValue
        let abs = Swift.abs(doubleVal)
        let sign = doubleVal < 0 ? "-" : ""

        if abs >= 1_000_000_000 {
            return String(format: "%@$%.1fB", sign, abs / 1_000_000_000)
        } else if abs >= 10_000_000 {
            return String(format: "%@$%.0fM", sign, abs / 1_000_000)
        } else if abs >= 1_000_000 {
            return String(format: "%@$%.1fM", sign, abs / 1_000_000)
        }
        // Under 1M: show full number, no cents
        return compactFormatter.string(from: amount) ?? "$0"
    }

    /// Color for positive/negative amounts
    static func isPositive(_ amount: NSDecimalNumber?) -> Bool {
        guard let amount = amount else { return true }
        return amount.compare(NSDecimalNumber.zero) != .orderedAscending
    }
}
