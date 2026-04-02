import Foundation

extension Date {
    /// Parse MS Money date format (ISO 8601 local datetime)
    static func fromMoneyString(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        // Skip invalid "far future" dates Money uses as sentinel values
        if string.hasPrefix("+10000") || string.hasPrefix("10000") {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        if let date = formatter.date(from: string) {
            return date
        }

        // Try without time
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        return dateOnly.date(from: string)
    }

    /// Format for display in transaction lists
    var shortDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    /// Format for section headers (month/year)
    var monthYearDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: self)
    }

    /// First day of the month
    var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }
}
