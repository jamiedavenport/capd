import Foundation
import Synchronization
import Testing

@testable import CapdKit

@Suite("Taxonomy consolidation")
struct TaxonomyConsolidationTests {
    @Test("Below the interval with tags within the cap, the model is never woken")
    func notDue() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seedTagged(store, [("A", "swift"), ("B", "databases")])
            var taxonomy = try store.taxonomy()
            taxonomy.tags = ["swift", "databases"]
            taxonomy.taggedSinceConsolidation = TagService.consolidationInterval - 1
            try store.saveTaxonomy(taxonomy)

            let calls = Mutex(0)
            let service = TagService(
                store: store,
                tagger: StubReviser { _ in
                    calls.withLock { $0 += 1 }
                    return TaxonomyRevision(keep: ["swift"], merges: [:])
                })

            #expect(try await service.consolidateIfNeeded() == false)
            #expect(calls.withLock { $0 } == 0)
        }
    }

    @Test("A due sweep merges, drops, and requeues mechanically")
    func dueSweep() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seedTagged(
                store,
                [
                    ("Swift piece", "swift"),
                    ("SwiftUI piece", "swiftui"),
                    ("Both", "swift swiftui"),
                    ("Doomed", "gadgets"),
                    ("Nothing applied", nil),
                ])
            var taxonomy = try store.taxonomy()
            taxonomy.tags = ["swift", "swiftui", "gadgets"]
            taxonomy.taggedSinceConsolidation = TagService.consolidationInterval
            try store.saveTaxonomy(taxonomy)

            let service = TagService(
                store: store,
                tagger: StubReviser { usage in
                    #expect(usage.map(\.tag).sorted() == ["gadgets", "swift", "swiftui"])
                    return TaxonomyRevision(keep: ["swift"], merges: ["swiftui": "swift"])
                })

            #expect(try await service.consolidateIfNeeded() == true)

            let revised = try store.taxonomy()
            #expect(revised.version == taxonomy.version + 1)
            #expect(revised.tags == ["swift"])
            #expect(revised.taggedSinceConsolidation == 0)

            let rows = try await store.reader.read { db in try Capture.fetchAll(db) }
            let byID = { (id: Int64) in rows.first { $0.id == id } }
            #expect(byID(ids[0])?.tagList == ["swift"])
            #expect(byID(ids[0])?.tagsVersion == revised.version)
            #expect(byID(ids[1])?.tagList == ["swift"])
            #expect(byID(ids[2])?.tagList == ["swift"])

            // The dropped tag and the previously-empty capture both go back in the
            // queue for re-tagging under the new vocabulary.
            #expect(byID(ids[3])?.tags == nil)
            #expect(byID(ids[3])?.tagsVersion == 0)
            #expect(byID(ids[4])?.tagsVersion == 0)
            #expect(
                Set(try store.untaggedCaptures(limit: 10).compactMap(\.id))
                    == [ids[3], ids[4]])
        }
    }

    @Test("More tags in use than the cap triggers a sweep before the interval")
    func overflowTriggers() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let tags = (1...Taxonomy.maxTags + 1).map { "tag\($0)" }
            try seedTagged(store, tags.map { ("Capture \($0)", $0) })
            var taxonomy = try store.taxonomy()
            taxonomy.tags = tags
            taxonomy.taggedSinceConsolidation = 1
            try store.saveTaxonomy(taxonomy)

            let service = TagService(
                store: store,
                tagger: StubReviser { usage in
                    TaxonomyRevision(
                        keep: Array(usage.map(\.tag).sorted().prefix(Taxonomy.maxTags)),
                        merges: [:])
                })

            #expect(try await service.consolidateIfNeeded() == true)
            #expect(try store.taxonomy().tags.count <= Taxonomy.maxTags)
        }
    }

    @Test("Row rewrites hold across write batches")
    func batchedRewrite() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seedTagged(store, (1...5).map { ("Capture \($0)", "old") })
            var taxonomy = try store.taxonomy()
            taxonomy.version = 2
            taxonomy.tags = ["new"]
            try store.applyTaxonomyRevision(
                mapping: ["old": "new"], taxonomy: taxonomy, batchSize: 2)

            let rows = try await store.reader.read { db in try Capture.fetchAll(db) }
            #expect(rows.allSatisfy { $0.tagList == ["new"] && $0.tagsVersion == 2 })
        }
    }

    @Test("The revision is sanitized before it touches anything")
    func sanitization() {
        let revision = TaxonomyRevision(
            keep: ["Swift", "swift", "Machine Learning", "###"]
                + (1...Taxonomy.maxTags).map { "filler\($0)" },
            merges: [
                "swiftui": "swift",
                "swift": "swift",
                "gone": "not-kept",
                "##": "swift",
            ])

        let (keep, mapping) = TagService.sanitize(revision)

        #expect(keep.count == Taxonomy.maxTags)
        #expect(keep[0] == "swift")
        #expect(keep[1] == "machine-learning")
        #expect(mapping["swiftui"] == "swift")
        #expect(mapping["swift"] == "swift")
        #expect(mapping["gone"] == nil)
        #expect(mapping["machine-learning"] == "machine-learning")
    }
}

private struct StubReviser: Tagger {
    let revise: @Sendable ([TagUsage]) async throws -> TaxonomyRevision

    init(revise: @escaping @Sendable ([TagUsage]) async throws -> TaxonomyRevision) {
        self.revise = revise
    }

    func availability() -> TaggerAvailability { .available }

    func assignTags(
        _ input: TaggingInput, taxonomy: [String], mayInventNew: Bool
    ) async throws -> [String] {
        []
    }

    func reviseTaxonomy(_ usage: [TagUsage]) async throws -> TaxonomyRevision {
        try await revise(usage)
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-consolidation-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(StoragePaths(root: root))
}

/// Seeds terminal captures with fixed tags; a nil tag list means processed-but-empty
/// (`tags_version` above zero with no tags).
@discardableResult
private func seedTagged(_ store: Store, _ rows: [(title: String, tags: String?)]) throws
    -> [Int64]
{
    try store.dbPool.write { db in
        try rows.map { entry in
            var capture = Capture(
                kind: .link,
                url: "https://example.com/x",
                host: "example.com",
                title: entry.title,
                tags: entry.tags,
                tagsVersion: 1,
                enrichmentState: .ok,
                createdAt: Date())
            try capture.insert(db)
            return capture.id!
        }
    }
}
