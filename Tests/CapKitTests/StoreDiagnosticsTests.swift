import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("Store diagnostics")
struct StoreDiagnosticsTests {
    @Test("Enrichment counts group every state, absent states omitted")
    func enrichmentCounts() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try insert(into: store, states: [.ok, .ok, .pending, .failed])

            let counts = try store.enrichmentCounts()

            #expect(counts == [.ok: 2, .pending: 1, .failed: 1])
        }
    }

    @Test("The average enrichment duration comes from completed attempts only")
    func averageEnrichmentSeconds() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            #expect(try store.averageEnrichmentSeconds() == nil)

            let start = Date(timeIntervalSince1970: 1_772_000_000)
            try store.dbPool.write { db in
                var enriched = capture(state: .ok, createdAt: start)
                enriched.lastAttemptAt = start
                enriched.updatedAt = start.addingTimeInterval(4)
                try enriched.insert(db)

                // Pending, and never attempted: both excluded from the average.
                var queued = capture(state: .pending, createdAt: start)
                try queued.insert(db)
            }

            let average = try #require(try store.averageEnrichmentSeconds())
            #expect(abs(average - 4) < 0.1)
        }
    }

    @Test("A healthy database passes the integrity check and reports a size")
    func integrityAndSize() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try insert(into: store, states: [.ok])

            #expect(try store.checkIntegrity() == ["ok"])
            #expect(store.databaseBytes() > 0)
        }
    }

    @Test("Rebuilding the search index keeps existing captures findable")
    func rebuildSearchIndex() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try store.dbPool.write { db in
                var row = capture(state: .ok, createdAt: Date())
                row.title = "structured concurrency"
                try row.insert(db)
            }

            #expect(try store.rebuildSearchIndex() == 1)

            let hits = try SearchService(store: store).search(SearchQuery(text: "concurrency"))
            #expect(hits.count == 1)
        }
    }

    @Test("The orphan sweep removes stale unreferenced assets and spares the rest")
    func orphanSweep() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let distantPast = Date(timeIntervalSinceNow: -86_400)

            try writeAsset(at: "aa/referenced.png", in: paths, modified: distantPast)
            try writeAsset(at: "bb/orphan.png", in: paths, modified: distantPast)
            try writeAsset(at: "cc/fresh-orphan.png", in: paths, modified: Date())

            try store.dbPool.write { db in
                var kept = capture(state: .ok, createdAt: Date())
                kept.kind = .image
                kept.assetPath = "aa/referenced.png"
                try kept.insert(db)

                var missing = capture(state: .ok, createdAt: Date())
                missing.kind = .image
                missing.assetPath = "dd/gone.png"
                try missing.insert(db)
            }

            let sweep = try store.sweepOrphanAssets()

            #expect(sweep.removedPaths == ["bb/orphan.png"])
            #expect(sweep.missingCaptureIDs == [2])
            let referenced = paths.assetURL(forRelativePath: "aa/referenced.png")
            let fresh = paths.assetURL(forRelativePath: "cc/fresh-orphan.png")
            #expect(FileManager.default.fileExists(atPath: referenced.path))
            #expect(FileManager.default.fileExists(atPath: fresh.path))
        }
    }
}

private func capture(state: EnrichmentState, createdAt: Date) -> Capture {
    Capture(
        kind: .link,
        url: "https://example.com/\(UUID().uuidString)",
        enrichmentState: state,
        createdAt: createdAt)
}

private func insert(into store: Store, states: [EnrichmentState]) throws {
    try store.dbPool.write { db in
        for state in states {
            var row = capture(state: state, createdAt: Date())
            try row.insert(db)
        }
    }
}

private func writeAsset(at relativePath: String, in paths: StoragePaths, modified: Date) throws {
    let url = paths.assetURL(forRelativePath: relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("png".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}
