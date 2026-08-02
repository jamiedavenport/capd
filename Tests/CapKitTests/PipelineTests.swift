import AppKit
import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("Processing pipeline")
struct PipelineTests {
    @Test("OCR applies only to an image capture holding an asset")
    func ocrAppliesOnlyToImageCapturesWithAssets() {
        let step = OCRStep()

        #expect(
            step.applies(
                to: Capture(kind: .image, assetPath: "ab/digest.png", createdAt: wholeSecond)))
        #expect(!step.applies(to: Capture(kind: .image, createdAt: wholeSecond)))
        #expect(!step.applies(to: Capture(kind: .link, createdAt: wholeSecond)))
        #expect(!step.applies(to: Capture(kind: .text, createdAt: wholeSecond)))
    }

    @Test("The step reads text off a rendered image")
    func stepReadsRenderedText() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: renderedPNG("PTARMIGAN HUSBANDRY"))
            ).capture

            let result = try await OCRStep().run(capture, context: ProcessingContext(paths: paths))

            let text = try #require(result.ocrText)
            #expect(text.lowercased().contains("ptarmigan"))
        }
    }

    @Test("An image with no text is a success with an empty string")
    func blankImageYieldsEmptyText() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: renderedPNG(nil))
            ).capture

            let result = try await OCRStep().run(capture, context: ProcessingContext(paths: paths))

            #expect(result.ocrText == "")
        }
    }

    @Test("Undecodable asset bytes are an error, not an empty result")
    func undecodableAssetThrows() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: undecodablePNG)
            ).capture

            await #expect(throws: (any Error).self) {
                try await OCRStep().run(capture, context: ProcessingContext(paths: paths))
            }
        }
    }

    @Test("The runner takes an image capture from pending to searchable")
    func runnerMakesImageTextSearchable() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: renderedPNG("PTARMIGAN HUSBANDRY"))
            ).capture
            let id = try #require(capture.id)

            let runner = EnrichmentRunner(store: store, steps: [OCRStep()])
            let processed = try #require(try await runner.process(captureID: id))

            #expect(processed.enrichmentState == .ok)
            #expect(processed.attemptCount == 1)
            #expect(processed.lastAttemptAt != nil)
            let text = try #require(processed.ocrText)
            #expect(text.lowercased().contains("ptarmigan"))

            let stored = try storedCapture(store, id: id)
            #expect(stored.enrichmentState == .ok)
            #expect(stored.ocrText == processed.ocrText)
            #expect(try matchingRowIDs(store, "ptarmigan") == [id])
        }
    }

    @Test("The runner lands a textless image on ok with an empty string")
    func runnerRecordsEmptyTextAsSuccess() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: renderedPNG(nil))
            ).capture
            let id = try #require(capture.id)

            let runner = EnrichmentRunner(store: store, steps: [OCRStep()])
            let processed = try #require(try await runner.process(captureID: id))

            #expect(processed.enrichmentState == .ok)
            #expect(processed.ocrText == "")
            #expect(try storedCapture(store, id: id).ocrText == "")
        }
    }

    @Test("A failing step lands the row on failed and surfaces the cause")
    func runnerRecordsFailureAndRethrows() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: undecodablePNG)
            ).capture
            let id = try #require(capture.id)

            let runner = EnrichmentRunner(store: store, steps: [OCRStep()])
            await #expect(throws: (any Error).self) {
                try await runner.process(captureID: id)
            }

            let stored = try storedCapture(store, id: id)
            #expect(stored.enrichmentState == .failed)
            #expect(stored.ocrText == nil)
            #expect(stored.attemptCount == 1)
        }
    }

    @Test("A capture can only be claimed once")
    func claimIsExclusive() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: undecodablePNG)
            ).capture
            let id = try #require(capture.id)

            let claimed = try #require(try store.claimForEnrichment(id: id))
            #expect(claimed.enrichmentState == .fetching)
            #expect(claimed.attemptCount == 1)
            #expect(try store.claimForEnrichment(id: id) == nil)
        }
    }

    @Test("A capture born terminal is not processed")
    func runnerSkipsNonPendingCaptures() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(text: "A standalone thought")
            ).capture
            let id = try #require(capture.id)

            let runner = EnrichmentRunner(store: store, steps: [OCRStep()])
            #expect(try await runner.process(captureID: id) == nil)

            let stored = try storedCapture(store, id: id)
            #expect(stored.enrichmentState == .ok)
            #expect(stored.attemptCount == 0)
        }
    }

    @Test("Completion without a claim is refused")
    func completionRequiresAClaim() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: undecodablePNG)
            ).capture
            let id = try #require(capture.id)

            #expect(throws: EnrichmentError.illegalTransition(from: .pending, to: .ok)) {
                try store.completeEnrichment(
                    id: id, result: StepResult(ocrText: "text"), state: .ok)
            }
            #expect(try storedCapture(store, id: id).enrichmentState == .pending)
        }
    }

    @Test(
        "A body step's status decides the enrichment state",
        arguments: [
            (BodyStatus.ok, EnrichmentState.ok),
            (BodyStatus.thin, EnrichmentState.thin),
            (BodyStatus.failed, EnrichmentState.failed),
        ])
    func runnerLandsBodyStatusOnTheRow(status: BodyStatus, expected: EnrichmentState) async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/a")
            ).capture
            let id = try #require(capture.id)

            let body = status == .failed ? nil : "the words on the page"
            let step = StubBodyStep(
                result: BodyExtractionResult(body: body, status: status, source: .fetch))
            let processed = try #require(
                try await EnrichmentRunner(store: store, steps: [step]).process(captureID: id))

            #expect(processed.enrichmentState == expected)
            #expect(processed.body == body)
            #expect(processed.bodyStatus == status)
            #expect(processed.bodySource == .fetch)
        }
    }

    @Test("processNext claims oldest first and reports an empty queue")
    func processNextDrainsInOrder() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)
            let first = try #require(
                try service.ingest(CaptureRequest(url: "https://example.com/a")).capture.id)
            let second = try #require(
                try service.ingest(CaptureRequest(url: "https://example.com/b")).capture.id)

            let runner = EnrichmentRunner(store: store, steps: [])
            #expect(try await runner.processNext()?.id == first)
            #expect(try await runner.processNext()?.id == second)
            #expect(try await runner.processNext() == nil)
        }
    }

    @Test("A pending capture with no applicable steps still completes")
    func runnerWithoutStepsCompletes() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: undecodablePNG)
            ).capture
            let id = try #require(capture.id)

            let runner = EnrichmentRunner(store: store, steps: [])
            let processed = try #require(try await runner.process(captureID: id))

            #expect(processed.enrichmentState == .ok)
            #expect(processed.ocrText == nil)
        }
    }
}

private struct StubBodyStep: ProcessingStep {
    let result: BodyExtractionResult

    func applies(to capture: Capture) -> Bool {
        capture.kind == .link
    }

    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        StepResult(bodyExtraction: result)
    }
}

private let undecodablePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

private let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)

private func renderedPNG(_ text: String?) throws -> Data {
    let image = NSImage(size: NSSize(width: 900, height: 200), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        if let text {
            (text as NSString).draw(
                at: NSPoint(x: 24, y: 72),
                withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 48),
                    .foregroundColor: NSColor.black,
                ])
        }
        return true
    }
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func withTemporaryPaths(_ body: (StoragePaths) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-pipeline-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(StoragePaths(root: root))
}

private func storedCapture(_ store: Store, id: Int64) throws -> Capture {
    try #require(
        try store.reader.read { db in
            try Capture.fetchOne(db, key: id)
        })
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
