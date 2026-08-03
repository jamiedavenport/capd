import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("Dedupe")
struct DedupeTests {
    @Test(
        "Normalization strips what does not identify the page",
        arguments: [
            ("HTTPS://Example.COM/Path", "https://example.com/Path"),
            ("https://example.com/a#section", "https://example.com/a"),
            ("https://example.com:443/a", "https://example.com/a"),
            ("http://example.com:80/a", "http://example.com/a"),
            ("http://example.com:8080/a", "http://example.com:8080/a"),
            ("https://example.com/a?utm_source=tw&utm_campaign=x", "https://example.com/a"),
            ("https://example.com/a?fbclid=abc&q=1", "https://example.com/a?q=1"),
            ("https://example.com/a?b=2&a=1", "https://example.com/a?a=1&b=2"),
            ("https://example.com", "https://example.com/"),
            ("https://example.com/a/", "https://example.com/a/"),
            ("https://example.com/a?q=hello%20world", "https://example.com/a?q=hello%20world"),
            ("https://example.com/a?gclid=1&ref=nav", "https://example.com/a?ref=nav"),
        ])
    func normalizationCanonicalizes(input: String, expected: String) throws {
        let url = try #require(URL(string: input))
        #expect(URLNormalizer.normalize(url) == expected)
    }

    @Test("A re-capture with tracking params merges into the original row")
    func trackedURLVariantMerges() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            let second = try service.ingest(
                CaptureRequest(url: "https://example.com/a?utm_source=tw&utm_campaign=x#top"))

            guard case .alreadyCaptured(let merged, previousSeenAt: _) = second else {
                Issue.record("expected a merge, got \(second)")
                return
            }
            #expect(merged.id == first.id)
            #expect(merged.url == "https://example.com/a")
            #expect(try captureCount(store) == 1)
        }
    }

    @Test("A merge bumps seen_count and advances last_seen_at")
    func mergeBumpsCounters() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            _ = try service.ingest(
                CaptureRequest(url: "https://example.com/a", capturedAt: wholeSecond))
            let outcome = try service.ingest(
                CaptureRequest(url: "https://example.com/a", capturedAt: laterSecond))

            guard case .alreadyCaptured(let merged, let previousSeenAt) = outcome else {
                Issue.record("expected a merge, got \(outcome)")
                return
            }
            #expect(previousSeenAt == wholeSecond)
            #expect(merged.seenCount == 2)
            #expect(merged.lastSeenAt == laterSecond)
            #expect(merged.updatedAt == laterSecond)
            #expect(merged.createdAt == wholeSecond)

            let stored = try store.reader.read { db in try Capture.fetchOne(db) }
            #expect(stored == merged)
        }
    }

    @Test(
        "Re-capturing a broken fetch re-queues enrichment",
        arguments: [EnrichmentState.failed, .thin])
    func brokenFetchRetriesOnRecapture(state: EnrichmentState) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            try forceEnrichment(
                store, id: first.id, state: state, attempts: 3, lastAttemptAt: wholeSecond)

            let merged = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            #expect(merged.enrichmentState == .pending)
            #expect(merged.attemptCount == 0)
            #expect(merged.lastAttemptAt == nil)
        }
    }

    @Test("A healthy row is not re-enriched")
    func healthyRowIsNotReenriched() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            try forceEnrichment(store, id: first.id, state: .ok, attempts: 1)

            let merged = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            #expect(merged.enrichmentState == .ok)
            #expect(merged.attemptCount == 1)
            #expect(merged.seenCount == 2)
        }
    }

    @Test("A no-fetch re-capture leaves a failed row alone")
    func noFetchRecaptureDoesNotRetry() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            try forceEnrichment(
                store, id: first.id, state: .failed, attempts: 3, lastAttemptAt: wholeSecond)

            let merged = try service.ingest(
                CaptureRequest(url: "https://example.com/a", fetchBody: false)
            ).capture
            #expect(merged.enrichmentState == .failed)
            #expect(merged.attemptCount == 3)
            #expect(merged.seenCount == 2)
        }
    }

    @Test("A queued row keeps its place in line")
    func queuedRowKeepsAttempts() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            try forceEnrichment(
                store, id: first.id, state: .pending, attempts: 1, lastAttemptAt: wholeSecond)

            let merged = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            #expect(merged.enrichmentState == .pending)
            #expect(merged.attemptCount == 1)
            #expect(merged.lastAttemptAt == wholeSecond)
        }
    }

    @Test("The same text twice merges to one row")
    func sameTextMerges() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            _ = try service.ingest(CaptureRequest(text: "A standalone thought"))
            let second = try service.ingest(CaptureRequest(text: "A standalone thought"))

            guard case .alreadyCaptured(let merged, previousSeenAt: _) = second else {
                Issue.record("expected a merge, got \(second)")
                return
            }
            #expect(merged.seenCount == 2)
            #expect(try captureCount(store) == 1)
        }
    }

    @Test("The same image twice merges to one row and one asset")
    func sameImageMerges() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            _ = try service.ingest(CaptureRequest(imageData: samplePNG))
            let second = try service.ingest(CaptureRequest(imageData: samplePNG))

            guard case .alreadyCaptured(let merged, previousSeenAt: _) = second else {
                Issue.record("expected a merge, got \(second)")
                return
            }
            #expect(merged.seenCount == 2)
            #expect(try captureCount(store) == 1)
            #expect(try writtenAssets(paths).count == 1)
        }
    }

    @Test("A merge fills empty metadata and never overwrites it")
    func mergeFillsMetadataGapsOnly() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            _ = try service.ingest(CaptureRequest(url: "https://example.com/a"))
            let second = try service.ingest(
                CaptureRequest(url: "https://example.com/a", title: "Kept", note: "Kept too")
            ).capture
            #expect(second.title == "Kept")
            #expect(second.note == "Kept too")

            let third = try service.ingest(
                CaptureRequest(url: "https://example.com/a", title: "Late", note: "Late too")
            ).capture
            #expect(third.title == "Kept")
            #expect(third.note == "Kept too")
        }
    }

    @Test("Different pages stay distinct rows")
    func distinctURLsDoNotMerge() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let first = try service.ingest(CaptureRequest(url: "https://example.com/a?page=2"))
            let second = try service.ingest(CaptureRequest(url: "https://example.com/a?page=3"))

            #expect(first == .captured(first.capture))
            #expect(second == .captured(second.capture))
            #expect(try captureCount(store) == 2)
        }
    }

    @Test("A first capture reports itself as new")
    func firstCaptureIsNew() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/a"))

            #expect(outcome == .captured(outcome.capture))
            #expect(outcome.capture.seenCount == 1)
        }
    }
}

private let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

/// Comparing a returned capture against its stored row needs a date that survives the round
/// trip, and GRDB stores dates as strings that stop at the millisecond.
private let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)
private let laterSecond = Date(timeIntervalSince1970: 1_700_500_000)

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-dedupe-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func captureCount(_ store: Store) throws -> Int {
    try store.reader.read { db in
        try Capture.fetchCount(db)
    }
}

private func writtenAssets(_ paths: StoragePaths) throws -> [URL] {
    let enumerated = FileManager.default.enumerator(
        at: paths.assetsDirectory, includingPropertiesForKeys: [.isRegularFileKey])
    guard let enumerated else { return [] }
    return enumerated.compactMap { $0 as? URL }.filter { url in
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

private func forceEnrichment(
    _ store: Store, id: Int64?, state: EnrichmentState, attempts: Int, lastAttemptAt: Date? = nil
) throws {
    let id = try #require(id)
    try store.dbPool.write { db in
        var row = try #require(try Capture.fetchOne(db, key: id))
        row.enrichmentState = state
        row.attemptCount = attempts
        row.lastAttemptAt = lastAttemptAt
        try row.update(db)
    }
}
