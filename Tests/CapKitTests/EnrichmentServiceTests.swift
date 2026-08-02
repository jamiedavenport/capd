import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("EnrichmentService")
struct EnrichmentServiceTests {
    @Test("Claiming a pending capture starts an attempt")
    func claimStartsAnAttempt() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try pendingLink(in: store)

            let claimed = try #require(
                try EnrichmentService(store: store).claim(id, now: wholeSecond))

            #expect(claimed.enrichmentState == .fetching)
            #expect(claimed.attemptCount == 1)
            #expect(claimed.lastAttemptAt == wholeSecond)
            #expect(claimed.updatedAt == wholeSecond)

            let stored = try store.reader.read { db in try Capture.fetchOne(db, key: id) }
            #expect(stored == claimed)
        }
    }

    @Test("A capture can only be claimed once")
    func secondClaimIsANoOp() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)

            #expect(try service.claim(id) != nil)
            #expect(try service.claim(id) == nil)
        }
    }

    @Test("A capture born terminal is not claimable")
    func terminalCaptureIsNotClaimable() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/a", fetchBody: false))

            let id = try #require(outcome.capture.id)
            #expect(try EnrichmentService(store: store).claim(id) == nil)
        }
    }

    @Test("Claiming or completing a capture that does not exist goes nowhere")
    func unknownCaptureGoesNowhere() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let result = BodyExtractionResult(body: "words", status: .ok, source: .fetch)

            #expect(try service.claim(99) == nil)
            #expect(throws: EnrichmentError.captureNotFound(99)) {
                try service.complete(99, with: result)
            }
        }
    }

    @Test("A good body lands in the row and the full-text index")
    func completeOKWritesBodyAndIndexes() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)
            try service.claim(id, now: wholeSecond)

            let result = BodyExtractionResult(
                body: "An essay about ptarmigans", status: .ok, source: .tab)
            let completed = try service.complete(id, with: result, now: wholeSecond)

            #expect(completed.body == "An essay about ptarmigans")
            #expect(completed.bodyStatus == .ok)
            #expect(completed.bodySource == .tab)
            #expect(completed.enrichmentState == .ok)
            #expect(completed.attemptCount == 1)
            #expect(completed.updatedAt == wholeSecond)
            #expect(try matchingRowIDs(store, "ptarmigans") == [id])

            let stored = try store.reader.read { db in try Capture.fetchOne(db, key: id) }
            #expect(stored == completed)
        }
    }

    @Test("A thin body is kept, flagged as thin")
    func completeThinKeepsTheBody() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)
            try service.claim(id)

            let result = BodyExtractionResult(
                body: "Sign in to continue", status: .thin, source: .fetch)
            let completed = try service.complete(id, with: result)

            #expect(completed.body == "Sign in to continue")
            #expect(completed.bodyStatus == .thin)
            #expect(completed.enrichmentState == .thin)
        }
    }

    @Test("A failed extraction records the failure and loses nothing")
    func completeFailedKeepsTheCapture() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(
                    url: "https://example.com/a",
                    text: "A quoted phrase",
                    title: "A title"))
            let id = try #require(outcome.capture.id)
            try service.claim(id)

            let result = BodyExtractionResult(body: nil, status: .failed, source: .fetch)
            let completed = try service.complete(id, with: result)

            #expect(completed.body == nil)
            #expect(completed.bodyStatus == .failed)
            #expect(completed.bodySource == .fetch)
            #expect(completed.enrichmentState == .failed)
            #expect(completed.url == "https://example.com/a")
            #expect(completed.title == "A title")
            #expect(completed.selection == "A quoted phrase")
        }
    }

    @Test("Completing a capture nobody claimed is an illegal transition")
    func completeWithoutClaimIsRefused() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try pendingLink(in: store)
            let result = BodyExtractionResult(body: "words", status: .ok, source: .tab)

            #expect(throws: EnrichmentError.illegalTransition(from: .pending, to: .ok)) {
                try EnrichmentService(store: store).complete(id, with: result)
            }
        }
    }
}

/// GRDB stores dates as strings that stop at the millisecond, so round-trip comparisons
/// need a whole second.
private let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)

private func pendingLink(in store: Store) throws -> Int64 {
    let outcome = try CaptureService(store: store).ingest(
        CaptureRequest(url: "https://example.com/a"))
    return try #require(outcome.capture.id)
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-enrichment-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func matchingRowIDs(_ store: Store, _ query: String) throws -> [Int64] {
    try store.reader.read { db in
        try Int64.fetchAll(
            db,
            sql: """
                SELECT rowid FROM \(Schema.capturesFTS)
                WHERE \(Schema.capturesFTS) MATCH ?
                """,
            arguments: [query])
    }
}
