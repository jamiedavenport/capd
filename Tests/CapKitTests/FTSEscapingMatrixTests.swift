import Foundation
import GRDB
import Testing

@testable import CapKit

/// One cell of the escaping matrix: text as it was captured, text as it is typed into the
/// search field, and whether the capture must come back.
struct EscapingCase: Sendable, CustomTestStringConvertible {
    let stored: String
    let query: String
    let found: Bool

    var testDescription: String {
        "\(found ? "hit" : "miss"): \"\(stored)\" ⟵ \"\(query)\""
    }
}

/// Round-trips FTS5 syntax, LIKE wildcards, and non-ASCII text through capture and search.
///
/// The malformed-input suite proves hostile queries never throw; this matrix pins the other
/// half of the contract: content and queries full of special characters still *match*, with
/// the same meaning on every surface.
@Suite("FTS escaping matrix")
struct FTSEscapingMatrixTests {
    static let matrix: [EscapingCase] = [
        // FTS5 string syntax typed into a query is literal, never an operator.
        EscapingCase(stored: "Read \"Gödel, Escher, Bach\" twice", query: "\"gödel", found: true),
        EscapingCase(stored: "Gödel Escher Bach", query: "godel escher", found: true),
        EscapingCase(stored: "naïve façade résumé", query: "naive facade resume", found: true),
        EscapingCase(stored: "AND OR NOT NEAR", query: "AND", found: true),
        EscapingCase(stored: "boolean AND gates", query: "boolean AND gates", found: true),
        EscapingCase(stored: "NEAR(5) proximity syntax", query: "NEAR(5)", found: true),
        EscapingCase(stored: "Wildcard star* semantics", query: "star*", found: true),
        EscapingCase(stored: "(parenthetical remarks)", query: "(parenthetical)", found: true),
        EscapingCase(stored: "caret^power notation", query: "caret^power", found: true),
        EscapingCase(stored: "half-open [0, 1) intervals", query: "[0, 1)", found: true),
        // A colon token whose prefix is no known filter stays in the text.
        EscapingCase(stored: "the foo:bar operator", query: "foo:bar", found: true),
        // Tokenizer-hostile identifiers: unicode61 splits on `_`, `.`, `-`, `+`, `#`.
        EscapingCase(stored: "snake_case identifiers", query: "snake_case", found: true),
        EscapingCase(stored: "Notes from swift.org today", query: "swift.org", found: true),
        EscapingCase(stored: "rock-and-roll history", query: "rock-and-roll", found: true),
        EscapingCase(stored: "Grokking C++ templates", query: "c++ templates", found: true),
        EscapingCase(stored: "100% cotton shirts", query: "100% cotton", found: true),
        EscapingCase(stored: "SELECT * FROM users", query: "select * from users", found: true),
        EscapingCase(
            stored: "'; DROP TABLE captures;--", query: "drop table captures", found: true),
        // Non-Latin scripts, including ones the porter stemmer cannot touch.
        EscapingCase(stored: "東京タワーの夜景", query: "東京タワー", found: true),
        EscapingCase(stored: "Emoji party 🎉 tonight", query: "🎉", found: true),
        // What must NOT match: wildcards and syntax are not an any-row pass.
        EscapingCase(stored: "plain text", query: "'; DROP TABLE captures;--", found: false),
        EscapingCase(stored: "plain text", query: "zzz%", found: false),
        EscapingCase(stored: "plain text", query: "_____", found: false),
        EscapingCase(stored: "plain text", query: "🎈", found: false),
    ]

    @Test("Stored and typed specials round-trip with literal meaning", arguments: matrix)
    func roundTrip(cell: EscapingCase) throws {
        try withStore { store in
            let ids = try seed(store, title: cell.stored)
            let service = SearchService(store: store)

            var hits: [SearchHit] = []
            #expect(throws: Never.self) {
                hits = try service.search(cell.query)
            }

            #expect(hits.map(\.capture.id) == (cell.found ? ids : []))
            let survivors = try store.dbPool.read { db in try Capture.fetchCount(db) }
            #expect(survivors == 1)
        }
    }

    /// The same cells must mean the same thing when the text sits in a page body, where
    /// only the full-text leg can reach it. Emoji-only queries are excluded: the tokenizer
    /// yields nothing for them, so a body is out of their reach by design and only URL and
    /// title substrings can answer.
    @Test(
        "Body-held specials are reachable through the full-text leg",
        arguments: matrix.filter { cell in
            cell.found && cell.query.contains { $0.isLetter || $0.isNumber }
        })
    func bodyRoundTrip(cell: EscapingCase) throws {
        try withStore { store in
            let ids = try seed(store, title: "Opaque label", body: cell.stored)

            let hits = try SearchService(store: store).search(cell.query)

            #expect(hits.map(\.capture.id) == ids)
        }
    }
}

private func withStore(_ body: (Store) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-escaping-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(Store(paths: StoragePaths(root: root)))
}

private func seed(_ store: Store, title: String, body: String? = nil) throws -> [Int64] {
    try store.dbPool.write { db in
        var capture = Capture(
            kind: .link,
            url: "https://matrix.example/x",
            host: "matrix.example",
            title: title,
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        try capture.insert(db)
        return [capture.id!]
    }
}
