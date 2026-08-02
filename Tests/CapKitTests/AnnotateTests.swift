import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("Annotate")
struct AnnotateTests {
    @Test("A note lands on the capture and persists")
    func noteLandsAndPersists() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)
            let id = try #require(
                try service.ingest(CaptureRequest(text: "A quoted phrase")).capture.id)

            let annotated = try service.annotate(id, note: "read this again")

            #expect(annotated.note == "read this again")
            let stored = try store.reader.read { db in try Capture.fetchOne(db, key: id) }
            #expect(stored?.note == "read this again")
        }
    }

    @Test("A whitespace note clears the existing one")
    func whitespaceNoteClears() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)
            let id = try #require(
                try service.ingest(
                    CaptureRequest(text: "A quoted phrase", note: "old note")
                ).capture.id)

            #expect(try service.annotate(id, note: "  \n").note == nil)
        }
    }

    @Test("Annotating a capture that does not exist refuses")
    func unknownCaptureRefuses() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            #expect(throws: CaptureError.notFound(99)) {
                try CaptureService(store: store).annotate(99, note: "anything")
            }
        }
    }

    @Test("The failed-enrichment count updates as captures fail")
    func failedEnrichmentCountsFollowFailures() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cap-annotate-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: StoragePaths(root: root))
        let id = try #require(
            try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/a")
            ).capture.id)

        var counts = store.failedEnrichmentCounts().makeAsyncIterator()
        #expect(try await counts.next() == 0)

        _ = try store.claimForEnrichment(id: id)
        _ = try store.completeEnrichment(id: id, result: StepResult(), state: .failed)

        while let count = try await counts.next() {
            if count == 1 { break }
        }
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-annotate-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}
