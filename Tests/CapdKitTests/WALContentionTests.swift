import Foundation
import GRDB
import Testing

@testable import CapdKit

/// Two real processes on one database file: `CapdTestHost` plays the CLI adding captures
/// while this process plays the agent claiming and completing them. WAL plus the busy
/// timeout is the whole cross-process story, so this is the test that proves it.
@Suite("Cross-process WAL contention")
struct WALContentionTests {
    private static let addCount = 200

    @Test("A second process adds while this one enriches", .timeLimit(.minutes(2)))
    func additionsLandWhileEnriching() async throws {
        try await withTemporaryPaths { paths in
            let store = try Store(paths: paths)

            let journalMode = try await store.reader.read { db in
                try String.fetchOne(db, sql: "PRAGMA journal_mode")
            }
            #expect(journalMode == "wal")

            let stderrPipe = Pipe()
            let helper = Process()
            helper.executableURL = try testHostURL()
            helper.arguments = [paths.root.path, "\(Self.addCount)", "burst"]
            helper.standardError = stderrPipe
            try helper.run()

            // No steps: enrichment is then pure store traffic — claim and complete are
            // two write transactions per row, all racing the helper's inserts.
            let enrichment = EnrichmentService(store: store, steps: [])
            var enriched = 0
            while true {
                let helperWasDone = !helper.isRunning
                let pending = try await store.reader.read { db in
                    try Int64.fetchAll(
                        db,
                        sql: """
                            SELECT id FROM \(Schema.captures)
                            WHERE enrichment_state = ?
                            """,
                        arguments: [EnrichmentState.pending.rawValue])
                }
                for id in pending {
                    if try await enrichment.process(captureID: id) != nil {
                        enriched += 1
                    }
                }
                if helperWasDone && pending.isEmpty { break }
                if pending.isEmpty {
                    try await Task.sleep(for: .milliseconds(5))
                }
            }

            // Not `waitUntilExit()`: other suites spawn their own children in parallel, and
            // it parks a thread beyond both task cancellation and the test's time limit.
            while helper.isRunning {
                try await Task.sleep(for: .milliseconds(10))
            }
            let stderr = String(
                decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(helper.terminationStatus == 0, "helper failed: \(stderr)")
            #expect(enriched == Self.addCount)

            let captures = try await store.reader.read { db in try Capture.fetchAll(db) }
            #expect(captures.count == Self.addCount)
            #expect(Set(captures.map(\.url)).count == Self.addCount)
            #expect(captures.allSatisfy { $0.enrichmentState == .ok })
            #expect(captures.allSatisfy { $0.attemptCount == 1 })
        }
    }
}

private final class BundleToken {}

/// The helper binary lands next to the test bundle in the build products directory.
private func testHostURL() throws -> URL {
    let url = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        .appendingPathComponent("CapdTestHost", isDirectory: false)
    try #require(
        FileManager.default.isExecutableFile(atPath: url.path),
        "CapdTestHost is not built at \(url.path)")
    return url
}

private func withTemporaryPaths(_ body: (StoragePaths) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-wal-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(StoragePaths(root: root))
}
