import Foundation
import GRDB
import Testing

@testable import CapKit

/// Byte-for-byte checks of the CLI's machine-readable output — the stable interface
/// scripts rely on. A failure here means that interface changed: either the change is
/// a bug, or these fixtures must be updated deliberately.
@Suite("cap CLI golden output")
struct CLIGoldenTests {
    @Test("list --json matches the golden file")
    func listJSON() throws {
        try withSeededRoot { root in
            let listed = try cap(["list", "--json"], root: root)
            #expect(listed.status == 0)
            #expect(listed.stdout == (try golden("list.json")))
        }
    }

    @Test("list --format tsv matches the golden file")
    func listTSV() throws {
        try withSeededRoot { root in
            let listed = try cap(["list", "--format", "tsv"], root: root)
            #expect(listed.status == 0)
            #expect(listed.stdout == (try golden("list.tsv")))
        }
    }

    @Test("search --json matches the golden file")
    func searchJSON() throws {
        try withSeededRoot { root in
            let searched = try cap(["search", "concurrency", "--json"], root: root)
            #expect(searched.status == 0)
            #expect(normalizingScores(searched.stdout) == (try golden("search.json")))
        }
    }

    @Test("export --json matches the golden file")
    func exportJSON() throws {
        try withSeededRoot { root in
            let exported = try cap(["export", "--json"], root: root)
            #expect(exported.status == 0)
            #expect(exported.stdout == (try golden("export.json")))
        }
    }

    private func withSeededRoot(_ body: (URL) throws -> Void) throws {
        try withScratchRoot { root in
            let store = try Store(paths: StoragePaths(root: root))
            try store.dbPool.write { db in
                for capture in Self.fixtures {
                    var capture = capture
                    try capture.insert(db)
                }
            }
            try body(root)
        }
    }

    /// Inserted directly, bypassing ingest, so every stored field appears with a fixed
    /// value. Millisecond-precision dates, because that is what the store keeps.
    private static let fixtures = [
        Capture(
            kind: .text,
            selection: "remember the milk",
            createdAt: Date(timeIntervalSince1970: 1_772_323_200.125)),
        Capture(
            kind: .image,
            title: "Kettle screenshot",
            ocrText: "error code 418: I'm a teapot",
            assetPath: "2026/03/kettle.png",
            sourceAppBundleID: "com.apple.Safari",
            enrichmentState: .ok,
            createdAt: Date(timeIntervalSince1970: 1_772_409_600.250)),
        Capture(
            kind: .link,
            url: "https://example.com/reading?id=42",
            host: "example.com",
            title: "Structured Concurrency Notes",
            note: "read before the talk",
            selection: "actors isolate state",
            body: "A deep dive into Swift concurrency, actors, and structured tasks.",
            sourceAppBundleID: "com.apple.Safari",
            enrichmentState: .ok,
            bodyStatus: .ok,
            bodySource: .fetch,
            attemptCount: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 1_772_496_060.750),
            contentHash: "2f7c9a1d8e5b4c3a",
            createdAt: Date(timeIntervalSince1970: 1_772_496_000.500),
            updatedAt: Date(timeIntervalSince1970: 1_772_496_060.750),
            lastSeenAt: Date(timeIntervalSince1970: 1_772_496_120.000),
            seenCount: 2),
    ]

    private func golden(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// bm25 scores are doubles whose last digits are not worth pinning across SQLite
    /// builds; the golden file asserts the field's presence, not its exact value.
    private func normalizingScores(_ output: String) -> String {
        output.replacingOccurrences(
            of: #""score" : -?[0-9.eE+-]+"#,
            with: #""score" : "<score>""#,
            options: .regularExpression)
    }
}
