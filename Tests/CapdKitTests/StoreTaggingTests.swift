import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("Store tagging")
struct StoreTaggingTests {
    @Test("A fresh store seeds an empty enabled taxonomy at version 1")
    func seededTaxonomy() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let taxonomy = try store.taxonomy()

            #expect(taxonomy.version == 1)
            #expect(taxonomy.tags.isEmpty)
            #expect(taxonomy.taggedSinceConsolidation == 0)
            #expect(taxonomy.taggingEnabled)
        }
    }

    @Test("The taxonomy round-trips through save and fetch")
    func taxonomyRoundTrip() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let saved = Taxonomy(
                version: 3,
                tags: ["swift", "databases", "reading"],
                taggedSinceConsolidation: 7,
                taggingEnabled: false,
                updatedAt: Date(timeIntervalSince1970: 1_772_000_000))

            try store.saveTaxonomy(saved)

            #expect(try store.taxonomy() == saved)
        }
    }

    @Test("Toggling tagging touches only the flag")
    func setTaggingEnabled() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let before = try store.taxonomy()

            try store.setTaggingEnabled(false)
            let disabled = try store.taxonomy()
            #expect(!disabled.taggingEnabled)
            #expect(disabled.version == before.version)
            #expect(disabled.tags == before.tags)

            try store.setTaggingEnabled(true)
            #expect(try store.taxonomy().taggingEnabled)
        }
    }

    @Test("A retag request resets automatic assignments but preserves imported tags")
    func requestedRetagging() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let automaticallyTagged = makeCapture(
                title: "Automatic", enrichmentState: .ok, tags: "swift")
            var processedWithoutTags = makeCapture(
                title: "No match", enrichmentState: .ok)
            processedWithoutTags.tagsVersion = 1
            var pinned = makeCapture(title: "Imported", enrichmentState: .ok, tags: "reading")
            pinned.tagsVersion = Capture.pinnedTagsVersion
            let ids = try seed(store, [automaticallyTagged, processedWithoutTags, pinned])

            try store.requestRetagging()
            #expect(try store.prepareRetagging(tags: ["planned"]) == 2)

            let captures = try store.reader.read { db in try Capture.fetchAll(db) }
            let automatic = captures.first { $0.id == ids[0] }
            #expect(automatic?.tags == nil)
            #expect(automatic?.tagsVersion == 0)
            #expect(captures.first { $0.id == ids[1] }?.tagsVersion == 0)
            #expect(captures.first { $0.id == ids[2] }?.tags == "reading")
            #expect(
                captures.first { $0.id == ids[2] }?.tagsVersion == Capture.pinnedTagsVersion)
            #expect(try store.prepareRetagging(tags: ["planned"]) == 0)
            #expect(try store.taxonomy().retagInProgress)
        }
    }

    @Test("Saving the taxonomy does not lose a concurrent retag request")
    func taxonomySavePreservesRetagRequest() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var capture = makeCapture(title: "Tagged", enrichmentState: .ok, tags: "swift")
            capture.tagsVersion = 1
            try seed(store, [capture])
            let taxonomy = try store.taxonomy()

            try store.requestRetagging()
            try store.saveTaxonomy(taxonomy)

            #expect(try store.prepareRetagging(tags: ["planned"]) == 1)
        }
    }

    @Test("Migration 002 adds the retag request to an existing tagging store")
    func migratesRetagRequest() throws {
        try withTemporaryPaths { paths in
            try paths.createDirectories()
            do {
                let pool = try DatabasePool(path: paths.databaseURL.path)
                var migrator = DatabaseMigrator()
                migrator.registerMigration("001", migrate: Migrations.createCaptures)
                try migrator.migrate(pool)
                try pool.close()
            }

            let store = try Store(paths: paths)
            try store.requestRetagging()

            let requested = try store.reader.read { db in
                try Bool.fetchOne(
                    db,
                    sql: "SELECT retag_requested FROM \(Schema.taxonomy) WHERE id = 1")
            }
            #expect(requested == true)
        }
    }

    @Test("Migration 003 adds persisted retag progress")
    func migratesRetagProgress() throws {
        try withTemporaryPaths { paths in
            try paths.createDirectories()
            do {
                let pool = try DatabasePool(path: paths.databaseURL.path)
                var migrator = DatabaseMigrator()
                migrator.registerMigration("001", migrate: Migrations.createCaptures)
                migrator.registerMigration("002", migrate: Migrations.addRetagRequest)
                try migrator.migrate(pool)
                try pool.close()
            }

            let store = try Store(paths: paths)

            #expect(try !store.taxonomy().retagInProgress)
            let persisted = try store.reader.read { db in
                try Bool.fetchOne(
                    db,
                    sql: "SELECT retag_in_progress FROM \(Schema.taxonomy) WHERE id = 1")
            }
            #expect(persisted == false)
        }
    }

    @Test("Retag planning samples are evenly spread and exclude pinned captures")
    func representativeRetaggingSamples() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var captures = (1...9).map {
                makeCapture(title: "Capture \($0)", enrichmentState: .ok)
            }
            captures[4].tags = "imported"
            captures[4].tagsVersion = Capture.pinnedTagsVersion
            _ = try seed(store, captures)

            let samples = try store.retaggingSamples(limit: 3)

            #expect(samples.map(\.title) == ["Capture 1", "Capture 4", "Capture 9"])
        }
    }

    @Test("Only terminal untagged captures are offered for tagging, oldest first")
    func untaggedCaptures() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "Old", enrichmentState: .ok),
                    makeCapture(title: "Still fetching", enrichmentState: .fetching),
                    makeCapture(title: "Queued", enrichmentState: .pending),
                    makeCapture(title: "Failed but taggable", enrichmentState: .failed),
                    makeCapture(title: "Already tagged", enrichmentState: .ok, tags: "swift"),
                    makeCapture(title: "Thin", enrichmentState: .thin),
                ])

            let untagged = try store.untaggedCaptures(limit: 10)
            #expect(untagged.map(\.id) == [ids[0], ids[3], ids[5]])

            let limited = try store.untaggedCaptures(limit: 1)
            #expect(limited.map(\.id) == [ids[0]])
        }
    }

    @Test("Completing a tagging writes the capture and the taxonomy in one step")
    func completeTagging() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Article", enrichmentState: .ok)])
            var taxonomy = try store.taxonomy()
            taxonomy.tags = ["swift", "reading"]
            taxonomy.taggedSinceConsolidation += 1

            try store.completeTagging(id: ids[0], tags: ["swift", "reading"], taxonomy: taxonomy)

            let capture = try store.reader.read { db in try Capture.fetchOne(db, key: ids[0]) }
            #expect(capture?.tags == "swift reading")
            #expect(capture?.tagList == ["swift", "reading"])
            #expect(capture?.tagsVersion == taxonomy.version)
            #expect(try store.taxonomy().taggedSinceConsolidation == 1)
            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("A capture no tag applies to is marked processed, not left in the queue")
    func completeTaggingWithNothingApplicable() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Odd one out", enrichmentState: .ok)])
            let taxonomy = try store.taxonomy()

            try store.completeTagging(id: ids[0], tags: [], taxonomy: taxonomy)

            let capture = try store.reader.read { db in try Capture.fetchOne(db, key: ids[0]) }
            #expect(capture?.tags == nil)
            #expect(capture?.tagList == [])
            #expect(capture?.tagsVersion == taxonomy.version)
            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("Completing the last queued capture ends the fixed retag pass")
    func completingRetagging() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Article", enrichmentState: .ok)])
            try store.requestRetagging()
            _ = try store.prepareRetagging(tags: ["swift"])
            let taxonomy = try store.taxonomy()
            #expect(taxonomy.retagInProgress)

            try store.completeTagging(id: ids[0], tags: ["swift"], taxonomy: taxonomy)

            #expect(try !store.taxonomy().retagInProgress)
        }
    }

    @Test("Tag usage counts every assignment, most used first, with capped samples")
    func tagUsage() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var captures = (1...7).map {
                makeCapture(title: "Swift piece \($0)", enrichmentState: .ok, tags: "swift")
            }
            captures.append(
                makeCapture(title: "Pair", enrichmentState: .ok, tags: "swift databases"))
            captures.append(makeCapture(title: nil, enrichmentState: .ok, tags: "databases"))
            try seed(store, captures)

            let usage = try store.tagUsage(sampleLimit: 5)

            #expect(usage.map(\.tag) == ["swift", "databases"])
            #expect(usage.map(\.count) == [8, 2])
            #expect(usage[0].sampleTitles.count == 5)
            #expect(usage[1].sampleTitles == ["Pair"])
        }
    }

    @Test("The initial database includes tagging and stays searchable")
    func initialSchemaIncludesTagging() throws {
        try withTemporaryPaths { paths in
            try paths.createDirectories()
            do {
                let pool = try DatabasePool(path: paths.databaseURL.path)
                var migrator = DatabaseMigrator()
                migrator.registerMigration("001", migrate: Migrations.createCaptures)
                try migrator.migrate(pool)
                try pool.write { db in
                    try db.execute(
                        sql: """
                            INSERT INTO captures
                                (kind, url, host, title, enrichment_state, body_status,
                                 attempt_count, created_at, updated_at, last_seen_at, seen_count)
                            VALUES
                                ('link', 'https://example.com/a', 'example.com', 'Fresh row',
                                 'ok', 'none', 0, :now, :now, :now, 1)
                            """,
                        arguments: ["now": Date()])
                }
                try pool.close()
            }

            let store = try Store(paths: paths)

            let capture = try #require(store.reader.read { db in try Capture.fetchOne(db) })
            #expect(capture.tags == nil)
            #expect(capture.tagsVersion == 0)

            let taxonomy = try store.taxonomy()
            #expect(taxonomy.version == 1)
            #expect(taxonomy.tags.isEmpty)

            let service = SearchService(store: store)
            #expect(try service.search("fresh").map(\.capture.id) == [capture.id])

            try store.completeTagging(id: capture.id!, tags: ["archive"], taxonomy: taxonomy)
            #expect(try service.search("tag:archive").map(\.capture.id) == [capture.id])
            #expect(try service.search("archive").map(\.capture.id) == [capture.id])
        }
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-tagging-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
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

private func makeCapture(
    title: String?,
    enrichmentState: EnrichmentState,
    tags: String? = nil
) -> Capture {
    Capture(
        kind: .link,
        url: "https://example.com/x",
        host: "example.com",
        title: title,
        tags: tags,
        tagsVersion: tags == nil ? 0 : 1,
        enrichmentState: enrichmentState,
        createdAt: Date()
    )
}
