import Foundation
import GRDB

/// A fragment of matched text with the matching ranges marked.
public struct Snippet: Equatable, Sendable {
    public let text: String
    public let highlights: [Range<String.Index>]
}

public struct SearchHit: Equatable, Sendable, Identifiable {
    public let capture: Capture
    /// Nil when the row was found by substring or filter alone, which yields no match ranges.
    public let snippet: Snippet?
    /// Raw bm25, where lower is a better match. Nil for rows the full-text index did not return.
    public let score: Double?

    public var id: Int64? { capture.id }
}

/// The one read path into the capture store.
///
/// The search window, the CLI, and any extension all go through this, so a query means the
/// same thing everywhere: full-text hits ranked by bm25 first, then a substring pass over
/// URLs and titles for what the porter tokenizer cannot reach.
public struct SearchService: Sendable {
    private let reader: any DatabaseReader
    private let parser: QueryParser

    public init(store: Store, parser: QueryParser = QueryParser()) {
        self.init(reader: store.reader, parser: parser)
    }

    init(reader: any DatabaseReader, parser: QueryParser = QueryParser()) {
        self.reader = reader
        self.parser = parser
    }

    public func capture(id: Int64) throws -> Capture? {
        try reader.read { db in try Capture.fetchOne(db, key: id) }
    }

    /// Finds the saved page represented by a URL after applying capture's canonicalization.
    public func capture(url: URL) throws -> Capture? {
        let hash = CaptureIdentity.contentHash(for: url)
        return try reader.read { db in
            try Capture.filter(Capture.CodingKeys.contentHash == hash).fetchOne(db)
        }
    }

    /// The whole library's size, for the search window's "N of M captures" footer.
    public func totalCaptureCount() throws -> Int {
        try reader.read { db in try Capture.fetchCount(db) }
    }

    public func search(
        _ rawQuery: String,
        limit: Int = QueryParser.defaultLimit
    ) throws -> [SearchHit] {
        try search(parser.parse(rawQuery, limit: limit))
    }

    public func search(_ query: SearchQuery) throws -> [SearchHit] {
        let limit = max(0, query.limit)
        guard limit > 0 else { return [] }

        // Trimmed here as well as in the parser, so a query built from CLI flags cannot mean
        // something different from the same query typed into the search field.
        var query = query
        query.text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // The two legs are merged here rather than in a UNION because bm25() and snippet()
        // are only legal in a query whose every arm matches the full-text index.
        return try reader.read { db in
            var hits = try rankedHits(query, limit: limit, in: db)
            guard hits.count < limit else { return hits }

            let matched = Set(hits.compactMap(\.capture.id))
            // A full limit, not the shortfall: up to `hits.count` of these are rows the ranked
            // leg already returned, and the merge below drops them.
            let extra = try scannedHits(query, limit: limit, in: db)

            for hit in extra {
                guard let id = hit.capture.id, !matched.contains(id) else { continue }
                hits.append(hit)
                if hits.count == limit { break }
            }
            return hits
        }
    }

    /// The full-text leg. Skipped when the text holds no indexable token, which is also what
    /// keeps malformed input from ever reaching SQLite's MATCH parser.
    private func rankedHits(
        _ query: SearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [SearchHit] {
        // Prefix matching, so results narrow while a word is being typed rather than only
        // once it is finished.
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query.text) else { return [] }

        var conditions = filters(query)
        conditions.clauses.insert("\(Schema.capturesFTS) MATCH ?", at: 0)
        conditions.arguments.insert(pattern, at: 0)
        conditions.arguments.append(limit)

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT \(Schema.captures).*,
                       \(Schema.bm25SQL) AS \(Self.rankColumn),
                       \(Self.snippetSQL) AS \(Self.snippetColumn)
                FROM \(Schema.captures)
                JOIN \(Schema.capturesFTS) ON \(Schema.capturesFTS).rowid = \(Self.column(.id))
                \(conditions.whereSQL)
                ORDER BY \(Self.rankColumn)
                LIMIT ?
                """,
            arguments: StatementArguments(conditions.arguments))

        return try rows.map { row in
            let raw: String? = row[Self.snippetColumn]
            return SearchHit(
                capture: try Capture(row: row),
                snippet: raw.map(Self.decodeSnippet),
                score: row[Self.rankColumn]
            )
        }
    }

    /// The substring leg, and — when there is no text at all — the plain recents leg.
    ///
    /// URLs are deliberately outside the full-text index because a porter tokenizer shreds
    /// them, so `ample.com` only ever finds `example.com` through here.
    private func scannedHits(
        _ query: SearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [SearchHit] {
        var conditions = filters(query)

        if !query.text.isEmpty {
            let needle = "%\(Self.escapingWildcards(query.text))%"
            // Past SQLITE_MAX_LIKE_PATTERN_LENGTH SQLite refuses the pattern outright, and a
            // search box takes whatever gets pasted into it. Abandoning the leg is the whole
            // leg, not just its clause — dropping only the clause would leave the filters
            // behind and answer a garbage query with every capture in the database.
            guard needle.utf8.count < Self.maxLikePatternBytes else { return [] }
            conditions.clauses.insert(
                """
                (\(Self.column(.url)) LIKE ? ESCAPE '\\' \
                OR \(Self.column(.title)) LIKE ? ESCAPE '\\')
                """, at: 0)
            conditions.arguments.insert(contentsOf: [needle, needle], at: 0)
        }
        conditions.arguments.append(limit)

        let captures = try Capture.fetchAll(
            db,
            sql: """
                SELECT * FROM \(Schema.captures)
                \(conditions.whereSQL)
                ORDER BY \(Self.column(.createdAt)) DESC, \(Self.column(.id)) DESC
                LIMIT ?
                """,
            arguments: StatementArguments(conditions.arguments))

        return captures.map { SearchHit(capture: $0, snippet: nil, score: nil) }
    }

    /// Table-qualified throughout: the full-text leg joins two tables that share column names.
    private func filters(_ query: SearchQuery) -> Conditions {
        let created = Self.column(.createdAt)
        var conditions = Conditions()

        if let site = query.site {
            let host = Self.column(.host)
            // NOCASE because hosts are case-insensitive and only the ingest path currently
            // lowercases the column. LIKE is NOCASE already, so without this the two arms
            // disagree with each other the moment a row arrives by any other route.
            conditions.clauses.append(
                "(\(host) = ? COLLATE NOCASE OR \(host) LIKE ? ESCAPE '\\')")
            conditions.arguments.append(site)
            conditions.arguments.append("%.\(Self.escapingWildcards(site))")
        }
        if let tag = query.tag {
            // Padded on both sides so the LIKE can only match a whole token: `tag:swift`
            // must not find `swiftui`. A NULL tags column concatenates to NULL, which the
            // LIKE rejects, so untagged rows drop out without their own clause.
            conditions.clauses.append("(' ' || \(Self.column(.tags)) || ' ') LIKE ? ESCAPE '\\'")
            conditions.arguments.append("% \(Self.escapingWildcards(tag)) %")
        }
        // Dates bind as Date: GRDB writes them in a fixed-width UTC format, so SQLite's
        // lexicographic string comparison is a chronological one too.
        if let after = query.createdAfter {
            conditions.clauses.append("\(created) >= ?")
            conditions.arguments.append(after)
        }
        if let before = query.createdBefore {
            conditions.clauses.append("\(created) < ?")
            conditions.arguments.append(before)
        }
        return conditions
    }

    private struct Conditions {
        var clauses: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []

        var whereSQL: String {
            clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
        }
    }
}

extension SearchService {
    /// Interlinear annotation anchors: format characters no captured text realistically holds,
    /// so one appearing in a snippet is unambiguously our own marker.
    private static let openMarker: Character = "\u{FFF9}"
    private static let closeMarker: Character = "\u{FFFB}"
    private static let ellipsis = "\u{2026}"
    private static let snippetTokens = 12

    /// SQLite's own `SQLITE_MAX_LIKE_PATTERN_LENGTH` default, in bytes.
    private static let maxLikePatternBytes = 50_000

    /// Not `rank`, which every FTS5 table already defines as a hidden column.
    private static let rankColumn = "bm25_rank"
    private static let snippetColumn = "match_snippet"

    private static func column(_ key: Capture.CodingKeys) -> String {
        "\(Schema.captures).\(key.rawValue)"
    }

    /// Column `-1` lets FTS5 pick whichever indexed column matched best.
    private static var snippetSQL: String {
        let arguments = [
            Schema.capturesFTS, "-1", "'\(openMarker)'", "'\(closeMarker)'", "'\(ellipsis)'",
            "\(snippetTokens)",
        ]
        return "snippet(\(arguments.joined(separator: ", ")))"
    }

    static func decodeSnippet(_ raw: String) -> Snippet {
        var characters: [Character] = []
        var spans: [(start: Int, end: Int)] = []
        var start: Int?

        for character in raw {
            if character == openMarker {
                start = start ?? characters.count
            } else if character == closeMarker {
                if let lower = start, lower < characters.count {
                    spans.append((lower, characters.count))
                }
                start = nil
            } else {
                characters.append(character)
            }
        }
        // A snippet truncated mid-highlight loses its closing marker; run the span to the end
        // rather than dropping the very match the user is looking at.
        if let lower = start, lower < characters.count {
            spans.append((lower, characters.count))
        }

        let text = String(characters)
        return Snippet(text: text, highlights: spans.compactMap { clamped($0, in: text) })
    }

    /// Character offsets can land off the end once markers are stripped and neighbouring
    /// scalars combine into one grapheme, so this clamps rather than trapping.
    private static func clamped(
        _ span: (start: Int, end: Int),
        in text: String
    ) -> Range<String.Index>? {
        guard
            let lower = text.index(text.startIndex, offsetBy: span.start, limitedBy: text.endIndex),
            let upper = text.index(text.startIndex, offsetBy: span.end, limitedBy: text.endIndex),
            lower < upper
        else {
            return nil
        }
        return lower..<upper
    }

    /// LIKE reads `%` and `_` as wildcards, so a literal one in a query has to be escaped.
    private static func escapingWildcards(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
