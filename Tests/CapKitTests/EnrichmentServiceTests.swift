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

    @Test("The oldest pending capture is claimed first")
    func claimNextTakesTheOldestFirst() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let first = try pendingLink(in: store, path: "a")
            let second = try pendingLink(in: store, path: "b")

            #expect(try service.claimNext()?.id == first)
            #expect(try service.claimNext()?.id == second)
            #expect(try service.claimNext() == nil)
        }
    }

    @Test("An abandoned claim goes back to the queue and can be claimed again")
    func reclaimReturnsAnAbandonedClaimToPending() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)
            let crashTime = Date(timeIntervalSinceNow: -600)
            try service.claim(id, now: crashTime)

            #expect(try service.reclaimStale() == 1)

            let reclaimed = try #require(
                try store.reader.read { try Capture.fetchOne($0, key: id) })
            #expect(reclaimed.enrichmentState == .pending)
            #expect(reclaimed.attemptCount == 1)

            let claimed = try #require(try service.claim(id))
            #expect(claimed.attemptCount == 2)
        }
    }

    @Test("A fresh claim survives an age-filtered reclaim")
    func freshClaimSurvivesReclaim() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)
            try service.claim(id)

            #expect(try service.reclaimStale() == 0)
            let stored = try #require(try store.reader.read { try Capture.fetchOne($0, key: id) })
            #expect(stored.enrichmentState == .fetching)
        }
    }

    @Test("An ageless reclaim takes everything, for agent startup")
    func agelessReclaimTakesFreshClaims() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)
            try service.claim(id)

            #expect(try service.reclaimStale(olderThan: nil) == 1)
            let stored = try #require(try store.reader.read { try Capture.fetchOne($0, key: id) })
            #expect(stored.enrichmentState == .pending)
        }
    }

    @Test("Reclaim gives up on a capture once its attempts are spent")
    func reclaimFailsACaptureAfterMaxAttempts() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            let id = try pendingLink(in: store)

            for attempt in 1...EnrichmentService.maxAttempts {
                let claimed = try #require(
                    try service.claim(id, now: Date(timeIntervalSinceNow: -600)))
                #expect(claimed.attemptCount == attempt)
                #expect(try service.reclaimStale() == 1)
            }

            let stored = try #require(try store.reader.read { try Capture.fetchOne($0, key: id) })
            #expect(stored.enrichmentState == .failed)
            #expect(stored.attemptCount == EnrichmentService.maxAttempts)
        }
    }

    @Test("Only pending captures count toward queue depth")
    func pendingCountCountsOnlyPending() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = EnrichmentService(store: store)
            _ = try pendingLink(in: store, path: "a")
            let claimed = try pendingLink(in: store, path: "b")
            try service.claim(claimed)

            #expect(try service.pendingCount() == 1)
        }
    }

    @Test("A completion carrying body and OCR results writes both")
    func completionMergesBodyAndOCR() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let id = try pendingLink(in: store)
            try EnrichmentService(store: store).claim(id)

            let merged = StepResult(
                ocrText: "words in a screenshot",
                bodyExtraction: BodyExtractionResult(body: "an essay", status: .ok, source: .fetch))
            let completed = try store.completeEnrichment(
                id: id, result: merged, state: merged.enrichmentState)

            #expect(completed.ocrText == "words in a screenshot")
            #expect(completed.body == "an essay")
            #expect(completed.bodyStatus == .ok)
            #expect(completed.bodySource == .fetch)
            #expect(completed.enrichmentState == .ok)
        }
    }
}

/// GRDB stores dates as strings that stop at the millisecond, so round-trip comparisons
/// need a whole second.
private let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)

private func pendingLink(in store: Store, path: String = "a") throws -> Int64 {
    let outcome = try CaptureService(store: store).ingest(
        CaptureRequest(url: "https://example.com/\(path)"))
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
