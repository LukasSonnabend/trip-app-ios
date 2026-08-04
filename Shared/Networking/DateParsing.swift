import Foundation

enum FlexibleDateFormatter {
    private static let isoWithOffset: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let naiveDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    static func parse(_ string: String) -> Date? {
        if let date = isoWithOffset.date(from: string) { return date }
        if let date = isoNoFractional.date(from: string) { return date }
        if let date = naiveDateTime.date(from: string) { return date }
        if let date = dateOnly.date(from: string) { return date }
        return nil
    }

    static func parseLocal(_ string: String) -> Date? {
        let stripped = string
            .replacingOccurrences(of: #"(Z|[+-]\d{2}(:?\d{2})?)$"#, with: "", options: .regularExpression)
        return parse(stripped)
    }

    static func parseInTimeZone(_ string: String, timeZone: TimeZone) -> Date? {
        if let date = isoWithOffset.date(from: string) { return date }
        if let date = isoNoFractional.date(from: string) { return date }
        let naiveFmt = DateFormatter()
        naiveFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        naiveFmt.locale = Locale(identifier: "en_US_POSIX")
        naiveFmt.timeZone = timeZone
        if let date = naiveFmt.date(from: string) { return date }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = timeZone
        return dateFmt.date(from: string)
    }

    static func displayString(_ string: String) -> String {
        guard let date = parse(string) else { return string }

        let hasTime = string.contains("T") && string.count > 11
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = extractTimeZone(from: string) ?? TimeZone.current

        if hasTime {
            f.dateStyle = .medium
            f.timeStyle = .short
        } else {
            f.dateStyle = .medium
            f.timeStyle = .none
        }
        return f.string(from: date)
    }

    private static func extractTimeZone(from string: String) -> TimeZone? {
        let pattern = try! Regex(#"([+-]\d{2}):(\d{2})$"#)
        guard let match = string.firstMatch(of: pattern),
              let hours = Int(match[1].substring ?? ""),
              let minutes = Int(match[2].substring ?? "") else { return nil }
        let seconds = hours * 3600 + (hours < 0 ? -minutes : minutes) * 60
        return TimeZone(secondsFromGMT: seconds)
    }

    static let strictISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
