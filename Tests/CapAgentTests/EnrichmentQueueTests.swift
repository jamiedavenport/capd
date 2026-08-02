import CapKit
import Foundation
import GRDB
import Testing

@testable import CapAgent

@Suite("EnrichmentQueue")
struct EnrichmentQueueTests {
    @Test("A 50-capture burst never exceeds three concurrent fetches on mains power")
    func burstStaysUnderTheMainsCap() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try ingestLinks(50, into: store)

            let gauge = Gauge()
            let runner = EnrichmentRunner(store: store, steps: [GaugedStep(gauge: gauge)])
            let queue = EnrichmentQueue(runner: runner, isOnMainsPower: { true })

            await queue.drain()

            #expect(await gauge.peak <= EnrichmentQueue.mainsPowerWidth)
            #expect(await gauge.peak > 1)
            #expect(try EnrichmentService(store: store).pendingCount() == 0)
            #expect(try states(in: store) == [.ok])
        }
    }

    @Test("On battery the queue drains one capture at a time")
    func batteryDrainsSerially() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try ingestLinks(10, into: store)

            let gauge = Gauge()
            let runner = EnrichmentRunner(store: store, steps: [GaugedStep(gauge: gauge)])
            let queue = EnrichmentQueue(runner: runner, isOnMainsPower: { false })

            await queue.drain()

            #expect(await gauge.peak == EnrichmentQueue.batteryWidth)
            #expect(try EnrichmentService(store: store).pendingCount() == 0)
        }
    }

    @Test("A throwing step fails its row without poisoning the queue")
    func throwingStepDoesNotPoisonTheQueue() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)
            let bad = try #require(
                try service.ingest(CaptureRequest(url: "https://example.com/bad")).capture.id)
            let good = try #require(
                try service.ingest(CaptureRequest(url: "https://example.com/good")).capture.id)

            let runner = EnrichmentRunner(store: store, steps: [TrapStep()])
            let queue = EnrichmentQueue(runner: runner, isOnMainsPower: { false })

            // The first drain dies on the bad row; the second finishes the queue.
            await queue.drain()
            await queue.drain()

            #expect(try state(of: bad, in: store) == .failed)
            #expect(try state(of: good, in: store) == .ok)
        }
    }
}

private actor Gauge {
    private var active = 0
    private(set) var peak = 0

    func enter() {
        active += 1
        peak = max(peak, active)
    }

    func exit() {
        active -= 1
    }
}

private struct GaugedStep: ProcessingStep {
    let gauge: Gauge

    func applies(to capture: Capture) -> Bool {
        capture.kind == .link
    }

    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        await gauge.enter()
        try await Task.sleep(for: .milliseconds(10))
        await gauge.exit()
        return StepResult(
            bodyExtraction: BodyExtractionResult(body: "a body", status: .ok, source: .fetch))
    }
}

private struct TrapStep: ProcessingStep {
    struct Trap: Error {}

    func applies(to capture: Capture) -> Bool {
        capture.kind == .link
    }

    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        if capture.url?.hasSuffix("bad") == true {
            throw Trap()
        }
        return StepResult(
            bodyExtraction: BodyExtractionResult(body: "a body", status: .ok, source: .fetch))
    }
}

private func ingestLinks(_ count: Int, into store: Store) throws {
    let service = CaptureService(store: store)
    for index in 0..<count {
        _ = try service.ingest(CaptureRequest(url: "https://example.com/page-\(index)"))
    }
}

private func states(in store: Store) throws -> [EnrichmentState] {
    try store.reader.read { db in
        try Capture.fetchAll(db).map(\.enrichmentState)
    }.uniqued()
}

private func state(of id: Int64, in store: Store) throws -> EnrichmentState? {
    try store.reader.read { db in
        try Capture.fetchOne(db, key: id)?.enrichmentState
    }
}

extension [EnrichmentState] {
    fileprivate func uniqued() -> [EnrichmentState] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-agent-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(StoragePaths(root: root))
}
