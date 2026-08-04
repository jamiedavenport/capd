import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("Store")
struct StoreTests {
    @Test("A fresh install lands the full schema in WAL mode")
    func freshInstall() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            try store.dbPool.read { db in
                let hasCaptures = try db.tableExists(Schema.captures)
                let hasFTS = try db.tableExists(Schema.capturesFTS)
                let hasTaxonomy = try db.tableExists(Schema.taxonomy)
                let triggers = try String.fetchSet(
                    db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
                let indexes = try Set(db.indexes(on: Schema.captures).map(\.name))
                let applied = try Migrations.migrator.appliedMigrations(db)
                let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
                let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys")

                #expect(hasCaptures)
                #expect(hasFTS)
                #expect(hasTaxonomy)
                #expect(
                    triggers == ["__captures_fts_ai", "__captures_fts_ad", "__captures_fts_au"])
                #expect(
                    indexes == [
                        "captures_on_content_hash", "captures_on_enrichment_state",
                        "captures_on_created_at", "captures_on_host", "captures_on_url",
                        "captures_on_title", "captures_on_tags_version",
                    ])
                #expect(applied == ["001", "002"])
                #expect(journalMode == "wal")
                #expect(foreignKeys == 1)
            }

            #expect(FileManager.default.fileExists(atPath: paths.assetsDirectory.path))
        }
    }

    @Test("Reopening an existing database is a no-op")
    func idempotentReopen() throws {
        try withTemporaryPaths { paths in
            let first = try Store(paths: paths)
            try first.dbPool.write { db in
                var capture = makeCapture(title: "Durable")
                try capture.insert(db)
            }

            let second = try Store(paths: paths)
            try second.dbPool.read { db in
                let applied = try Migrations.migrator.appliedMigrations(db)
                let count = try Capture.fetchCount(db)
                let survivor = try Capture.fetchOne(db)

                #expect(applied == ["001", "002"])
                #expect(count == 1)
                #expect(survivor?.title == "Durable")
            }
        }
    }

    @Test(
        "Enrichment transitions follow the state machine",
        arguments: EnrichmentState.allCases, EnrichmentState.allCases)
    func stateTransitions(from: EnrichmentState, to: EnrichmentState) {
        let legal: Set<Pair> = [
            Pair(.pending, .fetching), Pair(.pending, .failed),
            Pair(.fetching, .pending), Pair(.fetching, .ok),
            Pair(.fetching, .thin), Pair(.fetching, .failed),
            Pair(.ok, .pending), Pair(.thin, .pending), Pair(.failed, .pending),
        ]

        #expect(from.canTransition(to: to) == legal.contains(Pair(from, to)))
    }

    @Test("Only pending and fetching rows are in the queue")
    func queuedStates() {
        #expect(EnrichmentState.allCases.filter(\.isQueued) == [.pending, .fetching])
    }

    @Test("The database rejects a state outside the vocabulary")
    func checkConstraintsRejectUnknownStates() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try store.dbPool.write { db -> Int64 in
                var capture = makeCapture(title: "Guarded")
                try capture.insert(db)
                return capture.id!
            }

            for column in ["enrichment_state", "body_status", "body_source", "kind"] {
                #expect(throws: DatabaseError.self) {
                    try store.dbPool.write { db in
                        try db.execute(
                            sql: "UPDATE captures SET \(column) = 'bogus' WHERE id = ?",
                            arguments: [id])
                    }
                }
            }
        }
    }

    @Test("The full-text index tracks inserts, updates, and deletes")
    func fullTextIndexStaysInSync() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            let id = try store.dbPool.write { db -> Int64 in
                var capture = makeCapture(title: "Ptarmigan husbandry")
                try capture.insert(db)
                return capture.id!
            }

            #expect(try matchingRowIDs(store, "ptarmigan") == [id])

            try store.dbPool.write { db in
                try db.execute(
                    sql: "UPDATE captures SET title = 'Marmot husbandry' WHERE id = ?",
                    arguments: [id])
            }
            #expect(try matchingRowIDs(store, "ptarmigan").isEmpty)
            #expect(try matchingRowIDs(store, "marmot") == [id])

            try store.dbPool.write { db in
                try db.execute(sql: "DELETE FROM captures WHERE id = ?", arguments: [id])
            }
            #expect(try matchingRowIDs(store, "marmot").isEmpty)
        }
    }

    @Test("The porter tokenizer matches on word stems")
    func porterStemming() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try store.dbPool.write { db -> Int64 in
                var capture = makeCapture(title: "Indexing strategies")
                try capture.insert(db)
                return capture.id!
            }

            #expect(try matchingRowIDs(store, "index") == [id])
        }
    }

    /// The macron and caron cases are what `remove_diacritics=2` buys over the legacy default.
    @Test(
        "Accents fold away beyond the Latin-1 range",
        arguments: [
            ("Te reo Māori", "maori"),
            ("Karel Čapek bibliography", "capek"),
            ("Der Wärmepumpe Bericht", "warmepumpe"),
            ("Un café à Paris", "cafe"),
        ])
    func diacriticsAreFolded(title: String, query: String) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try store.dbPool.write { db -> Int64 in
                var capture = makeCapture(title: title)
                try capture.insert(db)
                return capture.id!
            }

            #expect(try matchingRowIDs(store, query) == [id])
        }
    }

    /// Stroked letters are not diacritics, so no mode folds them. Pinned as a known boundary.
    @Test("Stroked letters are not folded", arguments: [("Łódź city guide", "lodz")])
    func strokedLettersAreNotFolded(title: String, query: String) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try store.dbPool.write { db in
                var capture = makeCapture(title: title)
                try capture.insert(db)
            }

            #expect(try matchingRowIDs(store, query).isEmpty)
        }
    }

    @Test("bm25 weights rank a title match above a body match")
    func titleOutranksBody() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            let (titleMatch, bodyMatch) = try store.dbPool.write { db -> (Int64, Int64) in
                var inTitle = makeCapture(title: "Sqlite internals", body: "Unrelated prose")
                var inBody = makeCapture(title: "Unrelated prose", body: "Sqlite internals")
                try inTitle.insert(db)
                try inBody.insert(db)
                return (inTitle.id!, inBody.id!)
            }

            let ranked = try store.dbPool.read { db in
                try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT rowid FROM \(Schema.capturesFTS)
                        WHERE \(Schema.capturesFTS) MATCH ?
                        ORDER BY \(Schema.bm25SQL)
                        """,
                    arguments: ["sqlite"])
            }

            #expect(ranked == [titleMatch, bodyMatch])
        }
    }

    @Test("A repeated content hash is refused, but absent hashes are not")
    func contentHashIsUnique() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            try store.dbPool.write { db in
                var first = makeCapture(title: "First", contentHash: "abc123")
                try first.insert(db)
            }

            #expect(throws: DatabaseError.self) {
                try store.dbPool.write { db in
                    var duplicate = makeCapture(title: "Duplicate", contentHash: "abc123")
                    try duplicate.insert(db)
                }
            }

            try store.dbPool.write { db in
                var unhashedA = makeCapture(title: "Screenshot A")
                var unhashedB = makeCapture(title: "Screenshot B")
                try unhashedA.insert(db)
                try unhashedB.insert(db)
            }

            let count = try store.dbPool.read { db in
                try Capture.fetchCount(db)
            }
            #expect(count == 3)
        }
    }

    @Test("Every path derives from the storage root")
    func storagePathsDeriveFromRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/somewhere", isDirectory: true)
        let paths = StoragePaths(root: root)

        #expect(paths.databaseURL.path == "/tmp/somewhere/capd.sqlite")
        #expect(paths.assetsDirectory.path == "/tmp/somewhere/assets")
        #expect(
            paths.assetURL(forRelativePath: "ab/cd.png").path == "/tmp/somewhere/assets/ab/cd.png")

        let live = try StoragePaths.live
        #expect(live.root.pathComponents.suffix(2) == ["Application Support", "capd"])
    }

    @Test("A database from a newer build is refused rather than opened")
    func refusesSupersededDatabase() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try store.dbPool.write { db in
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES ('003')")
            }

            #expect(throws: StoreError.databaseIsNewerThanApp) {
                _ = try Store(paths: paths)
            }
        }
    }

    @Test("The write-ahead log survives the last connection closing")
    func walFilesPersistAfterClose() throws {
        try withTemporaryPaths { paths in
            try autoreleasepool {
                let store = try Store(paths: paths)
                try store.dbPool.write { db in
                    var capture = makeCapture(title: "Persisted")
                    try capture.insert(db)
                }
            }

            let wal = paths.databaseURL.path + "-wal"
            #expect(FileManager.default.fileExists(atPath: wal))
        }
    }

    @Test("Every column survives a write and read")
    func captureRoundTripsEveryColumn() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let created = Date(timeIntervalSince1970: 1_700_000_000)
            let attempted = Date(timeIntervalSince1970: 1_700_000_500)
            let seen = Date(timeIntervalSince1970: 1_700_001_000)

            let original = Capture(
                kind: .image,
                url: "https://example.com/a?b=c",
                host: "example.com",
                title: "Everything",
                note: "A note",
                selection: "A highlighted phrase",
                body: "The extracted body",
                ocrText: "Text lifted off the pixels",
                assetPath: "ab/cd.png",
                sourceAppBundleID: "com.apple.Safari",
                enrichmentState: .thin,
                bodyStatus: .thin,
                bodySource: .tab,
                attemptCount: 2,
                lastAttemptAt: attempted,
                contentHash: "deadbeef",
                createdAt: created,
                updatedAt: attempted,
                lastSeenAt: seen,
                seenCount: 3
            )

            try store.dbPool.write { db in
                var inserted = original
                try inserted.insert(db)
            }

            let stored = try store.reader.read { db in
                try Capture.fetchOne(db)
            }
            let round = try #require(stored)

            #expect(round.id != nil)
            var expected = original
            expected.id = round.id
            #expect(round == expected)
        }
    }

    /// The migrations freeze these into CHECK constraints and FTS columns, so widening one
    /// only reaches databases created afterwards. Adding a case must fail here, not at
    /// runtime — and a ranking change means a new migration that recreates the FTS table.
    @Test("The persisted vocabularies match what the migrations froze")
    func persistedVocabulariesArePinned() {
        #expect(CaptureKind.allCases.map(\.rawValue) == ["link", "text", "image"])
        #expect(
            EnrichmentState.allCases.map(\.rawValue)
                == ["pending", "fetching", "ok", "thin", "failed"])
        #expect(BodyStatus.allCases.map(\.rawValue) == ["none", "ok", "thin", "failed"])
        #expect(BodySource.allCases.map(\.rawValue) == ["tab", "fetch"])
        #expect(
            Schema.ranking.map(\.column)
                == ["title", "host", "tags", "note", "selection", "body", "ocr_text"])
        #expect(Schema.ranking.map(\.weight) == [4.0, 3.0, 3.0, 2.0, 2.0, 1.0, 1.0])
    }

    @Test("Timestamps default to the creation time when not supplied")
    func timestampsDefaultToCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_009_999)

        let defaulted = Capture(kind: .text, createdAt: created)
        #expect(defaulted.updatedAt == created)
        #expect(defaulted.lastSeenAt == created)
        #expect(defaulted.seenCount == 1)
        #expect(defaulted.enrichmentState == .pending)
        #expect(defaulted.bodyStatus == BodyStatus.none)

        let explicit = Capture(
            kind: .text, createdAt: created, updatedAt: later, lastSeenAt: later)
        #expect(explicit.updatedAt == later)
        #expect(explicit.lastSeenAt == later)
    }

    @Test("Deleting captures removes rows, index entries, and assets")
    func deleteCapturesCleansUp() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            let assetPath = "ab/abcdef.png"
            let assetURL = paths.assetURL(forRelativePath: assetPath)
            try FileManager.default.createDirectory(
                at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: assetURL)

            let link = try store.upsertCapture(makeCapture(title: "Doomed link")).capture
            let image = try store.upsertCapture(
                Capture(kind: .image, assetPath: assetPath, createdAt: Date())
            ).capture
            let survivor = try store.upsertCapture(makeCapture(title: "Survivor")).capture

            let deleted = try store.deleteCaptures(ids: [link.id!, image.id!, 999])
            #expect(Set(deleted.compactMap(\.id)) == Set([link.id!, image.id!]))
            #expect(!FileManager.default.fileExists(atPath: assetURL.path))

            try store.dbPool.read { db in
                let remaining = try Capture.fetchAll(db)
                #expect(remaining.map(\.id) == [survivor.id])
                let indexed = try Int.fetchOne(
                    db, sql: "SELECT count(*) FROM \(Schema.capturesFTS)")
                #expect(indexed == 1)
            }

            #expect(try store.deleteCaptures(ids: [999]).isEmpty)
        }
    }

    @Test("Requeueing ids moves only terminal rows and resets their attempts")
    func requeueCapturesRespectsStates() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var byState: [EnrichmentState: Int64] = [:]
            for state in EnrichmentState.allCases {
                let inserted = try store.upsertCapture(
                    Capture(
                        kind: .link,
                        url: "https://example.com/\(state.rawValue)",
                        enrichmentState: state,
                        attemptCount: 3,
                        createdAt: Date()))
                byState[state] = inserted.capture.id
            }

            let moved = try store.requeueCaptures(ids: Array(byState.values))
            #expect(moved == 3)

            try store.dbPool.read { db in
                for (was, id) in byState {
                    let row = try Capture.fetchOne(db, key: id)!
                    switch was {
                    case .ok, .thin, .failed:
                        #expect(row.enrichmentState == .pending)
                        #expect(row.attemptCount == 0)
                    case .pending, .fetching:
                        #expect(row.enrichmentState == was)
                        #expect(row.attemptCount == 3)
                    }
                }
            }
        }
    }

    @Test("Requeueing failures leaves healthy captures alone")
    func requeueFailedLeavesHealthyRows() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var byState: [EnrichmentState: Int64] = [:]
            for state in [EnrichmentState.ok, .thin, .failed, .pending] {
                let inserted = try store.upsertCapture(
                    Capture(
                        kind: .link,
                        url: "https://example.com/\(state.rawValue)",
                        enrichmentState: state,
                        createdAt: Date()))
                byState[state] = inserted.capture.id
            }

            #expect(try store.requeueFailedCaptures() == 2)

            try store.dbPool.read { db in
                let ok = try Capture.fetchOne(db, key: byState[.ok])!
                #expect(ok.enrichmentState == .ok)
                for state in [EnrichmentState.thin, .failed] {
                    let row = try Capture.fetchOne(db, key: byState[state])!
                    #expect(row.enrichmentState == .pending)
                }
            }

            #expect(try store.requeueFailedCaptures() == 0)
        }
    }
}

private struct Pair: Hashable {
    let from: EnrichmentState
    let to: EnrichmentState

    init(_ from: EnrichmentState, _ to: EnrichmentState) {
        self.from = from
        self.to = to
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-store-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func makeCapture(
    title: String,
    body: String? = nil,
    contentHash: String? = nil
) -> Capture {
    Capture(
        kind: .link,
        url: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))",
        host: "example.com",
        title: title,
        body: body,
        contentHash: contentHash,
        createdAt: Date()
    )
}

private func matchingRowIDs(_ store: Store, _ query: String) throws -> [Int64] {
    try store.dbPool.read { db in
        try Int64.fetchAll(
            db,
            sql: """
                SELECT rowid FROM \(Schema.capturesFTS)
                WHERE \(Schema.capturesFTS) MATCH ?
                """,
            arguments: [query])
    }
}
