import Foundation
import FoundationModels
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

    @Test("A manual request retags existing automatic assignments")
    func manualRetagging() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var capture = makeCapture(title: "SwiftUI field guide")
            capture.tags = "old"
            capture.tagsVersion = 1
            let ids = try seed(store, [capture])
            try store.requestRetagging()
            let service = TagService(store: store, tagger: StubTagger { _ in ["swift"] })

            #expect(try await service.tagNext() == 1)

            let retagged = try await store.reader.read { db in
                try Capture.fetchOne(db, key: ids[0])
            }
            let taxonomyVersion = try store.taxonomy().version
            #expect(retagged?.tagList == ["swift"])
            #expect(retagged?.tagsVersion == taxonomyVersion)
        }
    }

    @Test("A manual retag plans globally and keeps the vocabulary fixed across batches")
    func plannedManualRetagging() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            var first = makeCapture(title: "SwiftUI field guide")
            first.tags = "old"
            first.tagsVersion = 1
            var second = makeCapture(title: "Postgres tuning")
            second.tags = "old"
            second.tagsVersion = 1
            let ids = try seed(store, [first, second])
            try store.requestRetagging()

            let observations = Mutex([(taxonomy: [String], mayInvent: Bool)]())
            let service = TagService(
                store: store,
                tagger: PlanningStubTagger(
                    plan: { samples, _ in
                        #expect(
                            samples.map(\.title) == [
                                "SwiftUI field guide", "Postgres tuning",
                            ])
                        return ["Swift", "Databases"]
                    },
                    assign: { input, taxonomy, mayInvent in
                        observations.withLock {
                            $0.append((taxonomy: taxonomy, mayInvent: mayInvent))
                        }
                        return input.title?.hasPrefix("Swift") == true
                            ? ["swift"] : ["databases", "novel"]
                    }))

            #expect(try await service.tagNext(batch: 1) == 1)
            let during = try store.taxonomy()
            #expect(during.tags == ["swift", "databases"])
            #expect(during.retagInProgress)

            #expect(try await service.tagNext(batch: 1) == 1)
            let finished = try store.taxonomy()
            #expect(!finished.retagInProgress)
            #expect(finished.tags == ["swift", "databases"])
            #expect(finished.taggedSinceConsolidation == 0)
            #expect(observations.withLock { $0.allSatisfy { !$0.mayInvent } })

            let captures = try await store.reader.read { db in try Capture.fetchAll(db) }
            #expect(captures.first { $0.id == ids[0] }?.tagList == ["swift"])
            #expect(captures.first { $0.id == ids[1] }?.tagList == ["databases"])
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

    @Test("A rejected capture does not block later captures in its batch")
    func rejectedContentContinuesBatch() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let ids = try seed(
                store, [makeCapture(title: "Refused"), makeCapture(title: "Tag me")])
            let service = TagService(
                store: store,
                tagger: StubTagger { input in
                    if input.title == "Refused" { throw TaggingError.contentRejected }
                    return ["general"]
                })

            #expect(try await service.tagNext(batch: 2) == 2)

            let captures = try await store.reader.read { db in try Capture.fetchAll(db) }
            #expect(captures.first { $0.id == ids[0] }?.tagsVersion != 0)
            #expect(captures.first { $0.id == ids[1] }?.tagList == ["general"])
            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("Model refusals and unsupported languages are terminal content failures")
    func terminalFoundationModelErrors() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let errors: [LanguageModelSession.GenerationError] = [
            .refusal(refusal, context),
            .unsupportedLanguageOrLocale(context),
        ]

        for error in errors {
            #expect(FoundationModelTagger.mapped(error) as? TaggingError == .contentRejected)
        }
        #expect(
            FoundationModelTagger.mapped(.rateLimited(context)) as? TaggingError == nil)
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

private struct PlanningStubTagger: Tagger {
    let plan: @Sendable ([TaggingInput], [String]) async throws -> [String]
    let assign: @Sendable (TaggingInput, [String], Bool) async throws -> [String]

    func availability() -> TaggerAvailability { .available }

    func assignTags(
        _ input: TaggingInput, taxonomy: [String], mayInventNew: Bool
    ) async throws -> [String] {
        try await assign(input, taxonomy, mayInventNew)
    }

    func planTaxonomy(_ samples: [TaggingInput], existing: [String]) async throws -> [String] {
        try await plan(samples, existing)
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
