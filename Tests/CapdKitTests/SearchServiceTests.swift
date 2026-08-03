import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("Search service")
struct SearchServiceTests {
    /// The contract the design doc pins: a search box takes keystrokes, not well-formed
    /// FTS5, so nothing typed into it may reach SQLite's MATCH parser as syntax.
    @Test(
        "Malformed query text never throws",
        arguments: [
            "\"", "\"unclosed", "AND", "OR", "NOT", "NEAR", "a AND b", "*", "**", "(", ")",
            "()", "-", "^", "^foo", "title:", "column:value", "{a}", "+", "~", "\\", "%", "_",
            "'", ";", "--", "; DROP TABLE captures", "🐿️", "🐿️ 🌊", "!!!", "", " ", "\n",
            "\t\t", "a  b", "0", "-1", "..", "…", "北京", String(repeating: "x!*(", count: 1250),
        ])
    func malformedQueriesAreTotal(text: String) throws {
        try withSeededStore { store in
            let service = SearchService(store: store)

            #expect(throws: Never.self) {
                _ = try service.search(text)
            }
            let survivors = try store.dbPool.read { db in try Capture.fetchCount(db) }
            #expect(survivors == 2)
        }
    }

    @Test("A title match outranks a body match")
    func titleOutranksBody() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Unrelated prose", body: "Sqlite internals"),
                    makeCapture(title: "Sqlite internals", body: "Unrelated prose"),
                ])

            let hits = try SearchService(store: store).search("sqlite")

            #expect(hits.map(\.capture.id) == [ids[1], ids[0]])
            #expect(hits.allSatisfy { $0.score != nil })
        }
    }

    @Test("Full-text hits come before substring-only hits")
    func rankedLegLeadsTheFallback() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(
                        url: "https://other.com/pangolin", host: "other.com",
                        title: "Nothing to see"),
                    makeCapture(title: "Pangolin supply"),
                ])

            let hits = try SearchService(store: store).search("pangolin")

            #expect(hits.map(\.capture.id) == [ids[1], ids[0]])
            #expect(hits[0].score != nil)
            #expect(hits[1].score == nil)
            #expect(hits[1].snippet == nil)
        }
    }

    @Test("A URL substring the tokenizer cannot reach is found by the fallback")
    func urlSubstringFallback() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [makeCapture(url: "https://example.com/deep/path", title: "Nothing to see")])

            let hits = try SearchService(store: store).search("ample.com/deep")

            #expect(hits.map(\.capture.id) == ids)
            #expect(hits[0].score == nil)
        }
    }

    @Test("A row both legs find appears once, ranked")
    func legsDeduplicate() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Sqlite internals")])

            let hits = try SearchService(store: store).search("sqlite")

            #expect(hits.map(\.capture.id) == ids)
            #expect(hits[0].score != nil)
            #expect(hits[0].snippet != nil)
        }
    }

    @Test("LIKE wildcards in the query text are literal", arguments: ["%", "_", "a%c", "a_c"])
    func wildcardsDoNotMatchEverything(text: String) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            _ = try seed(store, [makeCapture(url: "https://example.com/abc", title: "Plain")])

            #expect(try SearchService(store: store).search(text).isEmpty)
        }
    }

    @Test("An escaped wildcard still matches its literal character")
    func literalWildcardMatches() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store, [makeCapture(url: "https://example.com/a%c", title: "Plain")])

            #expect(try SearchService(store: store).search("a%c").map(\.capture.id) == ids)
        }
    }

    /// A search field takes whatever is pasted into it. Past SQLite's LIKE pattern limit the
    /// substring leg used to fail the whole query with "LIKE or GLOB pattern too complex".
    @Test("A query far past SQLite's LIKE pattern limit still answers")
    func oversizedQuerySkipsTheSubstringLeg() throws {
        try withSeededStore { store in
            let service = SearchService(store: store)
            let pasted = "sqlite " + String(repeating: "lorem ipsum dolor ", count: 3_500)

            #expect(pasted.utf8.count > 50_000)
            let hits = try service.search(pasted)

            #expect(hits.isEmpty)
        }
    }

    /// Seeded past the ingest path, which is the one thing that lowercases the column today.
    /// Reading has to stand on its own or the two match arms disagree with each other.
    @Test("site: matches a host stored in mixed case")
    func siteFilterIsCaseInsensitive() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(host: "GitHub.com", title: "Root"),
                    makeCapture(host: "Gist.GitHub.com", title: "Subdomain"),
                ])

            let hits = try SearchService(store: store).search("site:github.com")

            #expect(Set(hits.map(\.capture.id)) == Set(ids))
        }
    }

    @Test("A wildcard in the site value matches only itself")
    func siteFilterEscapesWildcards() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(host: "a_c.com", title: "Literal"),
                    makeCapture(host: "sub.a_c.com", title: "Literal subdomain"),
                    makeCapture(host: "abc.com", title: "Wildcard would catch this"),
                    makeCapture(host: "sub.abc.com", title: "Wildcard would catch this too"),
                ])

            let hits = try SearchService(store: store).search("site:a_c.com")

            #expect(Set(hits.map(\.capture.id)) == Set([ids[0], ids[1]]))
        }
    }

    @Test("A backslash in the query text is matched literally")
    func backslashIsEscaped() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(url: "https://example.com/a\\b", title: "Backslash"),
                    makeCapture(url: "https://example.com/ab", title: "No backslash"),
                ])

            #expect(try SearchService(store: store).search("a\\b").map(\.capture.id) == [ids[0]])
        }
    }

    @Test("site: matches the host itself and its subdomains, nothing else")
    func siteFilter() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(host: "github.com", title: "Root"),
                    makeCapture(host: "gist.github.com", title: "Subdomain"),
                    makeCapture(host: "notgithub.com", title: "Impostor"),
                    makeCapture(host: "github.com.evil.net", title: "Suffix trick"),
                ])
            let service = SearchService(store: store)

            let scoped = try service.search("site:github.com")
            #expect(Set(scoped.map(\.capture.id)) == Set([ids[0], ids[1]]))

            #expect(try service.search("site:gist.github.com").map(\.capture.id) == [ids[1]])
            #expect(try service.search("site:absent.com").isEmpty)
        }
    }

    @Test("The site filter also constrains the full-text and substring legs")
    func siteFilterConstrainsBothLegs() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(
                        url: "https://example.com/sqlite", host: "example.com",
                        title: "Sqlite internals"),
                    makeCapture(
                        url: "https://other.com/sqlite", host: "other.com",
                        title: "Sqlite internals"),
                ])
            let service = SearchService(store: store)

            #expect(try service.search("sqlite site:example.com").map(\.capture.id) == [ids[0]])
            #expect(try service.search("com/sqlite site:other.com").map(\.capture.id) == [ids[1]])
        }
    }

    @Test("tag: matches whole tags only, and untagged rows drop out")
    func tagFilter() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Tagged", tags: "swift databases"),
                    makeCapture(title: "Near miss", tags: "swiftui"),
                    makeCapture(title: "Untagged"),
                ])
            let service = SearchService(store: store)

            #expect(try service.search("tag:swift").map(\.capture.id) == [ids[0]])
            #expect(try service.search("tag:swiftui").map(\.capture.id) == [ids[1]])
            #expect(try service.search("tag:databases").map(\.capture.id) == [ids[0]])
            #expect(try service.search("tag:absent").isEmpty)
        }
    }

    @Test("The tag filter also constrains the full-text leg, and tags are indexed text")
    func tagFilterConstrainsBothLegs() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Sqlite internals", tags: "databases"),
                    makeCapture(title: "Sqlite internals", tags: "reading"),
                ])
            let service = SearchService(store: store)

            #expect(try service.search("sqlite tag:databases").map(\.capture.id) == [ids[0]])
            // A tag is also plain searchable text, through the full-text index.
            #expect(try service.search("databases").map(\.capture.id) == [ids[0]])
        }
    }

    @Test("Date filters bound the day inclusively at the start and per keyword at the end")
    func dateFilters() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Before", createdAt: instant(2026, 3, 13, hour: 23)),
                    makeCapture(title: "Start of day", createdAt: instant(2026, 3, 14)),
                    makeCapture(title: "End of day", createdAt: instant(2026, 3, 14, hour: 23)),
                    makeCapture(title: "After", createdAt: instant(2026, 3, 15)),
                ])
            let service = SearchService(store: store, parser: QueryParser(calendar: utcCalendar))

            #expect(
                try service.search("after:2026-03-14").map(\.capture.id)
                    == [ids[3], ids[2], ids[1]])
            #expect(try service.search("before:2026-03-14").map(\.capture.id) == [ids[0]])
            #expect(
                try service.search("until:2026-03-14").map(\.capture.id)
                    == [ids[2], ids[1], ids[0]])
            #expect(
                try service.search("since:2026-03-14 until:2026-03-14").map(\.capture.id)
                    == [ids[2], ids[1]])
        }
    }

    @Test("An empty query returns recent captures, newest first")
    func emptyQueryReturnsRecents() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Oldest", createdAt: instant(2026, 1, 1)),
                    makeCapture(title: "Middle", createdAt: instant(2026, 2, 1)),
                    makeCapture(title: "Newest", createdAt: instant(2026, 3, 1)),
                ])
            let service = SearchService(store: store)

            let hits = try service.search("")
            #expect(hits.map(\.capture.id) == [ids[2], ids[1], ids[0]])
            #expect(hits.allSatisfy { $0.snippet == nil && $0.score == nil })

            #expect(try service.search("   ").map(\.capture.id) == [ids[2], ids[1], ids[0]])
            #expect(
                try service.search(SearchQuery(text: " \n ")).map(\.capture.id)
                    == [ids[2], ids[1], ids[0]])
        }
    }

    @Test("A filter-only query returns recents narrowed by the filter")
    func filterOnlyQuery() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(
                        host: "example.com", title: "Old", createdAt: instant(2026, 1, 1)),
                    makeCapture(
                        host: "example.com", title: "New", createdAt: instant(2026, 2, 1)),
                    makeCapture(host: "other.com", title: "Elsewhere"),
                ])
            let service = SearchService(store: store)

            #expect(try service.search("site:example.com").map(\.capture.id) == [ids[1], ids[0]])
        }
    }

    @Test("The limit caps the merged result, ranked hits first")
    func limitCapsMergedResults() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(url: "https://example.com/sqlite-a", title: "Nothing"),
                    makeCapture(url: "https://example.com/sqlite-b", title: "Nothing"),
                    makeCapture(title: "Sqlite internals"),
                ])
            let service = SearchService(store: store)

            #expect(try service.search("sqlite", limit: 1).map(\.capture.id) == [ids[2]])
            #expect(try service.search("sqlite", limit: 2).count == 2)
            #expect(try service.search("sqlite", limit: 0).isEmpty)
            #expect(try service.search("sqlite", limit: 9).count == 3)
        }
    }

    @Test("A snippet highlights the match and carries no markers")
    func snippetHighlightsTheMatch() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            _ = try seed(store, [makeCapture(title: "Sqlite internals explained")])

            let hits = try SearchService(store: store).search("internals")
            let snippet = try #require(hits.first?.snippet)
            let highlight = try #require(snippet.highlights.first)

            #expect(snippet.text == "Sqlite internals explained")
            #expect(snippet.text[highlight] == "internals")
            #expect(!snippet.text.contains("\u{FFF9}"))
            #expect(!snippet.text.contains("\u{FFFB}"))
        }
    }

    @Test("A long body is elided around the match")
    func longBodyIsElided() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let filler = String(repeating: "padding ", count: 200)
            _ = try seed(
                store,
                [makeCapture(title: "Notes", body: "\(filler)pangolin \(filler)")])

            let hits = try SearchService(store: store).search("pangolin")
            let snippet = try #require(hits.first?.snippet)

            #expect(snippet.text.contains("\u{2026}"))
            #expect(snippet.text.count < 200)
            #expect(snippet.highlights.count == 1)
            #expect(snippet.text[snippet.highlights[0]] == "pangolin")
        }
    }

    @Test("Emoji next to a match do not shift the highlight")
    func emojiDoNotCorruptRanges() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            _ = try seed(store, [makeCapture(title: "🐿️🌊 pangolin 🎈")])

            let hits = try SearchService(store: store).search("pangolin")
            let snippet = try #require(hits.first?.snippet)
            let highlight = try #require(snippet.highlights.first)

            #expect(snippet.text[highlight] == "pangolin")
        }
    }

    @Test("Snippet decoding survives markers that do not pair up")
    func decodeSnippetEdgeCases() {
        let plain = SearchService.decodeSnippet("nothing marked")
        #expect(plain == Snippet(text: "nothing marked", highlights: []))

        let unbalanced = SearchService.decodeSnippet("tail \u{FFF9}end")
        #expect(unbalanced.text == "tail end")
        #expect(unbalanced.text[unbalanced.highlights[0]] == "end")

        let orphanClose = SearchService.decodeSnippet("lone \u{FFFB}marker")
        #expect(orphanClose == Snippet(text: "lone marker", highlights: []))

        let empty = SearchService.decodeSnippet("\u{FFF9}\u{FFFB}")
        #expect(empty == Snippet(text: "", highlights: []))

        let nested = SearchService.decodeSnippet("\u{FFF9}a\u{FFF9}b\u{FFFB}")
        #expect(nested.text == "ab")
        #expect(nested.text[nested.highlights[0]] == "ab")

        let two = SearchService.decodeSnippet("\u{FFF9}a\u{FFFB} and \u{FFF9}b\u{FFFB}")
        #expect(two.highlights.count == 2)
        #expect(two.text[two.highlights[0]] == "a")
        #expect(two.text[two.highlights[1]] == "b")
    }

    /// Prefix matching happens on stems, not on the words that produced them: the tokenizer
    /// stores `run`, so `runni` can never be a prefix of anything in the index. The text lives
    /// in the body here, out of reach of the substring leg, so only the ranked leg can answer.
    @Test("Prefix matching runs against porter stems")
    func prefixMatchingIsStemmed() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store, [makeCapture(title: "Notes", body: "Running a marathon")])
            let service = SearchService(store: store)

            #expect(try service.search("run").map(\.capture.id) == ids)
            #expect(try service.search("runn").isEmpty)
            #expect(try service.search("runni").isEmpty)
        }
    }

    @Test("The raw-string and structured entry points agree")
    func entryPointsAgree() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let parser = QueryParser(calendar: utcCalendar)
            let ids = try seed(
                store,
                [
                    makeCapture(
                        host: "example.com", title: "Sqlite internals",
                        createdAt: instant(2026, 3, 14)),
                    makeCapture(
                        host: "other.com", title: "Sqlite internals",
                        createdAt: instant(2026, 3, 14)),
                ])
            let service = SearchService(store: store, parser: parser)

            let typed = try service.search("sqlite site:example.com since:2026-03-01")
            let structured = try service.search(
                SearchQuery(
                    text: "sqlite",
                    site: "example.com",
                    createdAfter: parser.inclusiveDayStart("2026-03-01")
                ))

            #expect(typed.map(\.capture.id) == [ids[0]])
            #expect(typed == structured)
        }
    }

    @Test("The total count spans the whole library, ignoring any query")
    func totalCount() throws {
        try withSeededStore { store in
            let count = try SearchService(store: store).totalCaptureCount()
            #expect(count == 2)
        }
    }

    @Test("A capture is fetchable by id")
    func captureByID() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Kept")])
            let service = SearchService(store: store)

            #expect(try service.capture(id: ids[0])?.title == "Kept")
            #expect(try service.capture(id: ids[0] + 1) == nil)
        }
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-search-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func withSeededStore(_ body: (Store) throws -> Void) throws {
    try withTemporaryPaths { paths in
        let store = try Store(paths: paths)
        _ = try seed(
            store,
            [
                makeCapture(
                    url: "https://example.com/sqlite", host: "example.com",
                    title: "Sqlite internals", body: "How the pager works"),
                makeCapture(host: "gist.github.com", title: "Running a marathon"),
            ])
        try body(store)
    }
}

@discardableResult
private func seed(_ store: Store, _ captures: [Capture]) throws -> [Int64] {
    try store.dbPool.write { db in
        try captures.map { capture in
            var row = capture
            try row.insert(db)
            return row.id!
        }
    }
}

/// The default URL is a fixed inert path rather than a UUID: UUID hex spells real words
/// (`cafe`, `beef`, `decade`), so a random one turns any such search term into a flake.
private func makeCapture(
    url: String? = nil,
    host: String? = "example.com",
    title: String? = nil,
    body: String? = nil,
    tags: String? = nil,
    createdAt: Date = Date()
) -> Capture {
    Capture(
        kind: .link,
        url: url ?? "https://example.com/x",
        host: host,
        title: title,
        body: body,
        tags: tags,
        tagsVersion: tags == nil ? 0 : 1,
        createdAt: createdAt
    )
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func instant(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    utcCalendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
