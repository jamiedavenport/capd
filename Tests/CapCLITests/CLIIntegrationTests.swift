import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("cap CLI")
struct CLIIntegrationTests {
    @Test("A link round-trips through add, search, and list")
    func addSearchListRoundTrip() throws {
        try withScratchRoot { root in
            let added = try cap(["add", "https://example.com/first", "--no-fetch"], root: root)
            #expect(added.status == 0)
            #expect(added.stdout.contains("Captured #1: https://example.com/first"))

            let searched = try cap(["search", "example", "--json"], root: root)
            #expect(searched.status == 0)
            let hits = try jsonArray(searched.stdout)
            #expect(hits.count == 1)
            let capture = try #require(hits.first)["capture"] as? [String: Any]
            #expect(capture?["url"] as? String == "https://example.com/first")
            #expect(capture?["created_at"] is String)

            let listed = try cap(["list"], root: root)
            #expect(listed.status == 0)
            #expect(listed.stdout.contains("#1"))
        }
    }

    @Test("Piped input becomes one capture per URL line")
    func stdinBulkURLs() throws {
        try withScratchRoot { root in
            let piped = """
                https://example.com/a
                https://example.com/b

                https://other.com/c
                """
            let added = try cap(["add", "-", "--no-fetch"], stdin: piped, root: root)
            #expect(added.status == 0)

            let listed = try cap(["list", "--json"], root: root)
            #expect(try jsonArray(listed.stdout).count == 3)
        }
    }

    @Test("Piped prose becomes a single text capture")
    func stdinText() throws {
        try withScratchRoot { root in
            let piped = "buy milk tomorrow\nand check https://example.com too"
            let added = try cap(["add", "-"], stdin: piped, root: root)
            #expect(added.status == 0)

            let searched = try cap(["search", "milk", "--json"], root: root)
            #expect(searched.status == 0)
            let hits = try jsonArray(searched.stdout)
            #expect(hits.count == 1)
            let capture = try #require(hits.first)["capture"] as? [String: Any]
            #expect(capture?["kind"] as? String == "text")
            #expect(capture?["selection"] as? String == piped)
        }
    }

    @Test("Re-adding a URL reports the existing capture and exits 0")
    func duplicateAdd() throws {
        try withScratchRoot { root in
            _ = try cap(["add", "https://example.com/dup", "--no-fetch"], root: root)
            let again = try cap(["add", "https://example.com/dup", "--no-fetch"], root: root)
            #expect(again.status == 0)
            #expect(again.stdout.contains("Already captured #1"))
        }
    }

    @Test("A non-http link is refused with exit 2")
    func invalidURL() throws {
        try withScratchRoot { root in
            let added = try cap(["add", "ftp://example.com/x"], root: root)
            #expect(added.status == 2)
            #expect(added.stderr.contains("Not a capturable link"))

            let listed = try cap(["list"], root: root)
            #expect(listed.status == 1)
        }
    }

    @Test("No results exits 1, and --json still emits a parseable empty array")
    func noResults() throws {
        try withScratchRoot { root in
            _ = try cap(["add", "https://example.com/a", "--no-fetch"], root: root)

            let plain = try cap(["search", "absent"], root: root)
            #expect(plain.status == 1)
            #expect(plain.stderr.contains("No results."))

            let json = try cap(["search", "absent", "--json"], root: root)
            #expect(json.status == 1)
            #expect(try jsonArray(json.stdout).isEmpty)
        }
    }

    @Test("Date and site flags narrow the search")
    func searchFilters() throws {
        try withScratchRoot { root in
            _ = try cap(["add", "https://example.com/a", "--no-fetch"], root: root)

            let today = Date().ISO8601Format(.init(timeZone: .current).year().month().day())
            #expect(try cap(["search", "--since", today], root: root).status == 0)
            #expect(try cap(["search", "--until", "2001-01-01"], root: root).status == 1)
            #expect(try cap(["search", "--site", "example.com"], root: root).status == 0)
            #expect(try cap(["search", "--site", "other.com"], root: root).status == 1)

            let malformed = try cap(["search", "--since", "2026-02-30"], root: root)
            #expect(malformed.status == 2)
            #expect(malformed.stderr.contains("YYYY-MM-DD"))
        }
    }

    @Test("TSV output is one escaped row per hit")
    func tsvOutput() throws {
        try withScratchRoot { root in
            _ = try cap(
                ["add", "https://example.com/a", "--no-fetch", "--title", "Tab\there"],
                root: root)

            let listed = try cap(["list", "--format", "tsv"], root: root)
            #expect(listed.status == 0)
            let fields = listed.stdout
                .trimmingCharacters(in: .newlines)
                .components(separatedBy: "\t")
            #expect(fields.count == 6)
            #expect(fields[0] == "1")
            #expect(fields[2] == "link")
            #expect(fields[4] == "Tab\\there")
        }
    }

    @Test("rm deletes by id and reports unknown ids with exit 1")
    func removeCaptures() throws {
        try withScratchRoot { root in
            _ = try cap(["add", "https://example.com/a", "--no-fetch"], root: root)

            let removed = try cap(["rm", "1"], root: root)
            #expect(removed.status == 0)
            #expect(removed.stdout.contains("Removed #1"))
            #expect(try cap(["list"], root: root).status == 1)

            let missing = try cap(["rm", "9"], root: root)
            #expect(missing.status == 1)
            #expect(missing.stderr.contains("No capture #9"))
        }
    }

    @Test("Export emits every capture as JSON or markdown")
    func export() throws {
        try withScratchRoot { root in
            _ = try cap(
                ["add", "https://example.com/a", "--no-fetch", "--title", "First"],
                root: root)
            _ = try cap(["add", "just a thought", "--note", "why"], root: root)

            let json = try cap(["export"], root: root)
            #expect(json.status == 0)
            let captures = try jsonArray(json.stdout)
            #expect(captures.count == 2)
            #expect(captures.allSatisfy { $0["created_at"] is String })

            let markdown = try cap(["export", "--format", "markdown"], root: root)
            #expect(markdown.status == 0)
            #expect(markdown.stdout.contains("- [First](https://example.com/a)"))
            #expect(markdown.stdout.contains("> just a thought"))
            #expect(markdown.stdout.contains("> why"))

        }
        try withScratchRoot { emptyRoot in
            let empty = try cap(["export"], root: emptyRoot)
            #expect(empty.status == 0)
            #expect(try jsonArray(empty.stdout).isEmpty)
        }
    }

    @Test("refetch requeues failed captures and exits 1 when there is nothing to do")
    func refetch() throws {
        try withScratchRoot { root in
            let idle = try cap(["refetch"], root: root)
            #expect(idle.status == 1)
            #expect(idle.stderr.contains("Nothing to refetch."))

            let store = try Store(paths: StoragePaths(root: root))
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/broken")
            ).capture
            try store.dbPool.write { db in
                try Capture
                    .filter(Capture.CodingKeys.id == capture.id)
                    .updateAll(
                        db, Capture.CodingKeys.enrichmentState.set(to: EnrichmentState.failed))
            }

            let requeued = try cap(["refetch"], root: root)
            #expect(requeued.status == 0)
            #expect(requeued.stdout.contains("Requeued 1 capture."))

            let state = try store.dbPool.read { db in
                try Capture.fetchOne(db, key: capture.id)!.enrichmentState
            }
            #expect(state == .pending)

            let missing = try cap(["refetch", "9"], root: root)
            #expect(missing.status == 1)
            #expect(missing.stderr.contains("No capture #9"))
        }
    }

    @Test("refetch by id is a forced refresh of a finished capture")
    func refetchByID() throws {
        try withScratchRoot { root in
            _ = try cap(["add", "https://example.com/a", "--no-fetch"], root: root)

            let requeued = try cap(["refetch", "1"], root: root)
            #expect(requeued.status == 0)
            #expect(requeued.stdout.contains("Requeued 1 capture."))
        }
    }

    @Test("--wait returns at once when nothing is queued, exits 4 when the queue stalls")
    func waitForEnrichment() throws {
        try withScratchRoot { root in
            let instant = try cap(
                ["add", "https://example.com/a", "--no-fetch", "--wait"], root: root)
            #expect(instant.status == 0)

            let stalled = try cap(
                ["add", "https://example.com/b", "--wait", "--timeout", "1"], root: root)
            #expect(stalled.status == 4)
            #expect(stalled.stderr.contains("cap-agent"))
        }
    }

    @Test("An unusable storage root exits 3")
    func storeUnavailable() throws {
        try withScratchRoot { root in
            let blocked = root.appendingPathComponent("blocked", isDirectory: false)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("not a directory".utf8).write(to: blocked)

            let listed = try cap(["list"], root: blocked)
            #expect(listed.status == 3)
            #expect(listed.stderr.contains("store is unavailable"))
        }
    }

    @Test("Usage errors exit 2 and the version flag exits 0")
    func usageAndVersion() throws {
        try withScratchRoot { root in
            #expect(try cap(["search", "--bogus"], root: root).status == 2)
            #expect(try cap(["nonsense"], root: root).status == 2)

            let version = try cap(["--version"], root: root)
            #expect(version.status == 0)
            #expect(version.stdout.contains(CapKit.version))

            let help = try cap([], root: root)
            #expect(help.status == 0)
            #expect(help.stdout.contains("SUBCOMMANDS"))
        }
    }
}

private final class BinaryLocator {}

/// The `cap` product lands in the same build directory as this test bundle.
private let capBinary = Bundle(for: BinaryLocator.self).bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("cap", isDirectory: false)

private struct CLIRun {
    let status: Int32
    let stdout: String
    let stderr: String
}

@discardableResult
private func cap(_ arguments: [String], stdin: String? = nil, root: URL) throws -> CLIRun {
    let process = Process()
    process.executableURL = capBinary
    process.arguments = arguments

    var environment = ProcessInfo.processInfo.environment
    environment["CAP_DIR"] = root.path
    process.environment = environment

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    if let stdin {
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
    } else {
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    // Drain before waiting, or a full pipe buffer deadlocks the child.
    let outData = try output.fileHandleForReading.readToEnd() ?? Data()
    let errData = try errors.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()

    return CLIRun(
        status: process.terminationStatus,
        stdout: String(decoding: outData, as: UTF8.self),
        stderr: String(decoding: errData, as: UTF8.self))
}

private func withScratchRoot(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-cli-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func jsonArray(_ text: String) throws -> [[String: Any]] {
    let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return try #require(parsed as? [[String: Any]])
}
