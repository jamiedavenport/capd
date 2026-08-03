import Foundation

/// A parsed search request: free text plus the filters that narrow it.
///
/// Both the typed query syntax and the CLI's flags produce one of these, so every surface
/// runs the same query against the same execution path.
public struct SearchQuery: Equatable, Sendable {
    /// The free text left over once filter tokens are removed.
    public var text: String
    /// A lowercased host. Matches the host itself and any subdomain of it.
    public var site: String?
    /// A lowercased tag, matched as a whole token of the capture's tag list.
    public var tag: String?
    /// Inclusive lower bound on `created_at`.
    public var createdAfter: Date?
    /// Exclusive upper bound on `created_at`.
    public var createdBefore: Date?
    public var limit: Int

    public init(
        text: String = "",
        site: String? = nil,
        tag: String? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        limit: Int = QueryParser.defaultLimit
    ) {
        self.text = text
        self.site = site
        self.tag = tag
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.limit = limit
    }
}

/// Splits a raw query string into free text and filters.
///
/// Parsing is total: anything that does not form a valid filter stays in the search text, so
/// a half-typed `after:2026-0` searches for that literal rather than failing.
public struct QueryParser: Sendable {
    public static let defaultLimit = 50

    /// Injected so that day boundaries are the user's, and so tests can pin a zone.
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ input: String, limit: Int = QueryParser.defaultLimit) -> SearchQuery {
        var query = SearchQuery(limit: limit)
        var words: [Substring] = []

        for token in input.split(whereSeparator: \.isWhitespace) {
            if apply(token, to: &query) { continue }
            words.append(token)
        }

        query.text = words.joined(separator: " ")
        return query
    }

    /// Midnight at the start of the given `YYYY-MM-DD` day, or nil if the date is not a real one.
    public func inclusiveDayStart(_ yyyyMMdd: String) -> Date? {
        guard let wanted = dayComponents(yyyyMMdd), let date = calendar.date(from: wanted) else {
            return nil
        }
        // `date(from:)` rolls a nonexistent day forward rather than refusing it, so 2026-02-30
        // silently becomes March. Round-tripping is what rejects it.
        let got = calendar.dateComponents([.year, .month, .day], from: date)
        guard got.year == wanted.year, got.month == wanted.month, got.day == wanted.day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    /// Midnight at the start of the day *after* the given one, so the day itself is included.
    public func exclusiveDayEnd(_ yyyyMMdd: String) -> Date? {
        guard let start = inclusiveDayStart(yyyyMMdd) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    /// Returns false when the token is not a filter, in which case it belongs to the text.
    private func apply(_ token: Substring, to query: inout SearchQuery) -> Bool {
        guard let colon = token.firstIndex(of: ":") else { return false }
        let value = token[token.index(after: colon)...]
        guard !value.isEmpty else { return false }

        switch token[..<colon].lowercased() {
        case "site":
            query.site = value.lowercased()
        case "tag":
            // A leading `#` is accepted because that's how people write tags elsewhere.
            let tag = value.drop(while: { $0 == "#" }).lowercased()
            guard !tag.isEmpty else { return false }
            query.tag = tag
        case "after", "since":
            guard let date = inclusiveDayStart(String(value)) else { return false }
            query.createdAfter = date
        case "before":
            guard let date = inclusiveDayStart(String(value)) else { return false }
            query.createdBefore = date
        case "until":
            guard let date = exclusiveDayEnd(String(value)) else { return false }
            query.createdBefore = date
        default:
            return false
        }
        return true
    }

    /// Strict `YYYY-MM-DD`. Hand-rolled rather than `DateFormatter` so that neither the
    /// user's locale nor a lenient parser can widen what counts as a date.
    private func dayComponents(_ yyyyMMdd: String) -> DateComponents? {
        let fields = yyyyMMdd.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3,
            fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
            let year = digits(fields[0]), let month = digits(fields[1]), let day = digits(fields[2])
        else {
            return nil
        }
        return DateComponents(year: year, month: month, day: day)
    }

    private func digits(_ field: Substring) -> Int? {
        guard field.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(field)
    }
}
