import Foundation

enum ClauditFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static let compactCurrencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    static func cost(_ value: Double) -> String {
        if value < 0.01 { return "$0.00" }
        if value < 10.0 { return currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00" }
        return compactCurrencyFormatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func costDetail(_ value: Double) -> String {
        if value < 0.01 { return "$0.00" }
        return currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    static func tokensWithUnit(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM tok", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK tok", Double(count) / 1_000)
        }
        return "\(count) tok"
    }

    static func duration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0s" }
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        let s = Int(interval) % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(s)s"
    }

    // ISO8601DateFormatter is not thread-safe; guard concurrent access with a lock
    private static let dateParserLock = NSLock()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let microsecondFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        dateParserLock.lock()
        defer { dateParserLock.unlock() }
        return isoFractional.date(from: string)
            ?? isoBasic.date(from: string)
            ?? microsecondFormatter.date(from: string)
    }

    static func formatISO8601(_ date: Date) -> String {
        dateParserLock.lock()
        defer { dateParserLock.unlock() }
        return isoBasic.string(from: date)
    }

    static func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Glob": return "doc.text.magnifyingglass"
        case "Grep": return "magnifyingglass"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "WebFetch": return "arrow.down.doc"
        default: return "wrench"
        }
    }
}
