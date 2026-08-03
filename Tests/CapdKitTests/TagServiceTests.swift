import Foundation
import Synchronization
import Testing

@testable import CapdKit

@Suite("Tag service")
struct TagServiceTests {
    @Test("Assignment writes tags, advances the queue, and grows the taxonomy")
    func assignment() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store,
                [
                    makeCapture(title: "SwiftUI field guide"),
                    makeCapture(title: "Postgres tuning"),
                ])
            let service = TagService(
                store: store,
                tagger: StubTagger { input in
                    input.title == "SwiftUI field guide" ? ["swift", "ui"] : ["databases"]
                })

            let processed = try await service.tagNext(batch: 10)

            #expect(processed == 2)
            let captures = try await store.reader.read { db in try Capture.fetchAll(db) }
            #expect(captures.first { $0.id == ids[0] }?.tagList == ["swift", "ui"])
            #expect(captures.first { $0.id == ids[1] }?.tagList == ["databases"])

            let taxonomy = try store.taxonomy()
            #expect(taxonomy.tags == ["swift", "ui", "databases"])
            #expect(taxonomy.taggedSinceConsolidation == 2)
            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("A full taxonomy stops inventions but keeps matches")
    func fullTaxonomy() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Something new")])
            var taxonomy = try store.taxonomy()
            taxonomy.tags = (1...Taxonomy.maxTags).map { "tag\($0)" }
            try store.saveTaxonomy(taxonomy)

            let service = TagService(
                store: store, tagger: StubTagger { _ in ["novel", "tag3", "unheard"] })
            _ = try await service.tagNext()

            let capture = try await store.reader.read { db in
                try Capture.fetchOne(db, key: ids[0])
            }
            #expect(capture?.tagList == ["tag3"])
            #expect(try store.taxonomy().tags.count == Taxonomy.maxTags)
        }
    }

    @Test("Disabled tagging processes nothing and never wakes the model")
    func disabledTagging() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seed(store, [makeCapture(title: "Waiting")])
            try store.setTaggingEnabled(false)

            let calls = Mutex(0)
            let service = TagService(
                store: store,
                tagger: StubTagger { _ in
                    calls.withLock { $0 += 1 }
                    return ["never"]
                })

            #expect(try await service.tagNext() == 0)
            #expect(calls.withLock { $0 } == 0)
            #expect(try store.untaggedCaptures(limit: 10).count == 1)
        }
    }

    @Test("An unavailable model leaves the queue untouched")
    func unavailableModel() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seed(store, [makeCapture(title: "Waiting")])
            let service = TagService(
                store: store,
                tagger: StubTagger(available: .unavailable(.appleIntelligenceOff)) { _ in
                    ["never"]
                })

            #expect(try await service.tagNext() == 0)
            #expect(try store.untaggedCaptures(limit: 10).count == 1)
        }
    }

    @Test("Rejected content is marked processed instead of hot-looping")
    func rejectedContent() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(store, [makeCapture(title: "Refused")])
            let service = TagService(
                store: store, tagger: StubTagger { _ in throw TaggingError.contentRejected })

            #expect(try await service.tagNext() == 1)

            let capture = try await store.reader.read { db in
                try Capture.fetchOne(db, key: ids[0])
            }
            #expect(capture?.tags == nil)
            #expect(capture?.tagsVersion != 0)
            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("A transient failure stops the batch and keeps the capture queued")
    func transientFailure() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seed(store, [makeCapture(title: "Flaky")])
            let service = TagService(
                store: store, tagger: StubTagger { _ in throw URLError(.timedOut) })

            await #expect(throws: URLError.self) {
                try await service.tagNext()
            }
            #expect(try store.untaggedCaptures(limit: 10).count == 1)
        }
    }

    @Test("The batch size caps one pass")
    func batchCap() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try seed(store, (1...5).map { makeCapture(title: "Capture \($0)") })
            let service = TagService(store: store, tagger: StubTagger { _ in ["general"] })

            #expect(try await service.tagNext(batch: 2) == 2)
            #expect(try store.untaggedCaptures(limit: 10).count == 3)
        }
    }

    @Test(
        "Candidates are normalized into single lowercase tokens",
        arguments: [
            ("Swift", "swift"),
            ("Machine Learning", "machine-learning"),
            ("  spaced  out  ", "spaced-out"),
            ("Café", "cafe"),
            ("C++", "c"),
            ("--edgy--", "edgy"),
            ("swift-ui", "swift-ui"),
        ])
    func normalization(raw: String, expected: String) {
        #expect(TagService.normalize(raw) == expected)
    }

    @Test(
        "Unsalvageable candidates are discarded",
        arguments: ["", "  ", "###", "--", String(repeating: "long", count: 10)])
    func discardedCandidates(raw: String) {
        #expect(TagService.normalize(raw) == nil)
    }

    @Test("Duplicates collapse and the per-capture cap holds")
    func acceptanceRules() {
        var taxonomy = Taxonomy(updatedAt: Date())

        let accepted = TagService.accept(
            ["Swift", "swift", "SWIFT", "ui", "web", "extra"],
            into: &taxonomy, mayInventNew: true)

        #expect(accepted == ["swift", "ui", "web"])
        #expect(taxonomy.tags == ["swift", "ui", "web"])
    }
}

private struct StubTagger: Tagger {
    var available: TaggerAvailability = .available
    let result: @Sendable (TaggingInput) async throws -> [String]

    init(
        available: TaggerAvailability = .available,
        result: @escaping @Sendable (TaggingInput) async throws -> [String]
    ) {
        self.available = available
        self.result = result
    }

    func availability() -> TaggerAvailability { available }

    func assignTags(
        _ input: TaggingInput, taxonomy: [String], mayInventNew: Bool
    ) async throws -> [String] {
        try await result(input)
    }

    func reviseTaxonomy(_ usage: [TagUsage]) async throws -> TaxonomyRevision {
        TaxonomyRevision(keep: [], merges: [:])
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-tagservice-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(StoragePaths(root: root))
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

private func makeCapture(title: String?) -> Capture {
    Capture(
        kind: .link,
        url: "https://example.com/x",
        host: "example.com",
        title: title,
        enrichmentState: .ok,
        createdAt: Date()
    )
}
