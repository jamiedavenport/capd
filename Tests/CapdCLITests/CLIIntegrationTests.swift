import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("capd CLI")
struct CLIIntegrationTests {
    @Test("A link round-trips through add, search, and list")
    func addSearchListRoundTrip() throws {
        try withScratchRoot { root in
            let added = try capd(["add", "https://example.com/first", "--no-fetch"], root: root)
            #expect(added.status == 0)
            #expect(added.stdout.contains("Captured #1: https://example.com/first"))

            let searched = try capd(["search", "example", "--json"], root: root)
            #expect(searched.status == 0)
            let hits = try jsonArray(searched.stdout)
            #expect(hits.count == 1)
            let capture = try #require(hits.first)["capture"] as? [String: Any]
            #expect(capture?["url"] as? String == "https://example.com/first")
            #expect(capture?["created_at"] is String)

            let listed = try capd(["list"], root: root)
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
            let added = try capd(["add", "-", "--no-fetch"], stdin: piped, root: root)
            #expect(added.status == 0)

            let listed = try capd(["list", "--json"], root: root)
            #expect(try jsonArray(listed.stdout).count == 3)
        }
    }

    @Test("Piped prose becomes a single text capture")
    func stdinText() throws {
        try withScratchRoot { root in
            let piped = "buy milk tomorrow\nand check https://example.com too"
            let added = try capd(["add", "-"], stdin: piped, root: root)
            #expect(added.status == 0)

            let searched = try capd(["search", "milk", "--json"], root: root)
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
            _ = try capd(["add", "https://example.com/dup", "--no-fetch"], root: root)
            let again = try capd(["add", "https://example.com/dup", "--no-fetch"], root: root)
            #expect(again.status == 0)
            #expect(again.stdout.contains("Already captured #1"))
        }
    }

    @Test("A non-http link is refused with exit 2")
    func invalidURL() throws {
        try withScratchRoot { root in
            let added = try capd(["add", "ftp://example.com/x"], root: root)
            #expect(added.status == 2)
            #expect(added.stderr.contains("Not a capturable link"))

            let listed = try capd(["list"], root: root)
            #expect(listed.status == 1)
        }
    }

    @Test("No results exits 1, and --json still emits a parseable empty array")
    func noResults() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let plain = try capd(["search", "absent"], root: root)
            #expect(plain.status == 1)
            #expect(plain.stderr.contains("No results."))

            let json = try capd(["search", "absent", "--json"], root: root)
            #expect(json.status == 1)
            #expect(try jsonArray(json.stdout).isEmpty)
        }
    }

    @Test("Date and site flags narrow the search")
    func searchFilters() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let today = Date().ISO8601Format(.init(timeZone: .current).year().month().day())
            #expect(try capd(["search", "--since", today], root: root).status == 0)
            #expect(try capd(["search", "--until", "2001-01-01"], root: root).status == 1)
            #expect(try capd(["search", "--site", "example.com"], root: root).status == 0)
            #expect(try capd(["search", "--site", "other.com"], root: root).status == 1)

            let malformed = try capd(["search", "--since", "2026-02-30"], root: root)
            #expect(malformed.status == 2)
            #expect(malformed.stderr.contains("YYYY-MM-DD"))
        }
    }

    @Test("TSV output is one escaped row per hit")
    func tsvOutput() throws {
        try withScratchRoot { root in
            _ = try capd(
                ["add", "https://example.com/a", "--no-fetch", "--title", "Tab\there"],
                root: root)

            let listed = try capd(["list", "--format", "tsv"], root: root)
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
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let removed = try capd(["rm", "1"], root: root)
            #expect(removed.status == 0)
            #expect(removed.stdout.contains("Removed #1"))
            #expect(try capd(["list"], root: root).status == 1)

            let missing = try capd(["rm", "9"], root: root)
            #expect(missing.status == 1)
            #expect(missing.stderr.contains("No capture #9"))
        }
    }

    @Test("Export emits every capture as JSON or markdown")
    func export() throws {
        try withScratchRoot { root in
            _ = try capd(
                ["add", "https://example.com/a", "--no-fetch", "--title", "First"],
                root: root)
            _ = try capd(["add", "just a thought", "--note", "why"], root: root)

            let json = try capd(["export"], root: root)
            #expect(json.status == 0)
            let captures = try jsonArray(json.stdout)
            #expect(captures.count == 2)
            #expect(captures.allSatisfy { $0["created_at"] is String })

            let markdown = try capd(["export", "--format", "markdown"], root: root)
            #expect(markdown.status == 0)
            #expect(markdown.stdout.contains("- [First](https://example.com/a)"))
            #expect(markdown.stdout.contains("> just a thought"))
            #expect(markdown.stdout.contains("> why"))

        }
        try withScratchRoot { emptyRoot in
            let empty = try capd(["export"], root: emptyRoot)
            #expect(empty.status == 0)
            #expect(try jsonArray(empty.stdout).isEmpty)
        }
    }

    @Test("refetch requeues failed captures and exits 1 when there is nothing to do")
    func refetch() throws {
        try withScratchRoot { root in
            let idle = try capd(["refetch"], root: root)
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

            let requeued = try capd(["refetch"], root: root)
            #expect(requeued.status == 0)
            #expect(requeued.stdout.contains("Requeued 1 capture."))

            let state = try store.dbPool.read { db in
                try Capture.fetchOne(db, key: capture.id)!.enrichmentState
            }
            #expect(state == .pending)

            let missing = try capd(["refetch", "9"], root: root)
            #expect(missing.status == 1)
            #expect(missing.stderr.contains("No capture #9"))
        }
    }

    @Test("refetch by id is a forced refresh of a finished capture")
    func refetchByID() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let requeued = try capd(["refetch", "1"], root: root)
            #expect(requeued.status == 0)
            #expect(requeued.stdout.contains("Requeued 1 capture."))
        }
    }

    @Test("--wait returns at once when nothing is queued, exits 4 when the queue stalls")
    func waitForEnrichment() throws {
        try withScratchRoot { root in
            let instant = try capd(
                ["add", "https://example.com/a", "--no-fetch", "--wait"], root: root)
            #expect(instant.status == 0)

            let stalled = try capd(
                ["add", "https://example.com/b", "--wait", "--timeout", "1"], root: root)
            #expect(stalled.status == 4)
            #expect(stalled.stderr.contains("capd-agent"))
        }
    }

    @Test("An unusable storage root exits 3")
    func storeUnavailable() throws {
        try withScratchRoot { root in
            let blocked = root.appendingPathComponent("blocked", isDirectory: false)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("not a directory".utf8).write(to: blocked)

            let listed = try capd(["list"], root: blocked)
            #expect(listed.status == 3)
            #expect(listed.stderr.contains("store is unavailable"))
        }
    }

    @Test("Usage errors exit 2 and the version flag exits 0")
    func usageAndVersion() throws {
        try withScratchRoot { root in
            #expect(try capd(["search", "--bogus"], root: root).status == 2)
            #expect(try capd(["list", "--format", "bogus"], root: root).status == 2)
            #expect(try capd(["nonsense"], root: root).status == 2)

            let version = try capd(["--version"], root: root)
            #expect(version.status == 0)
            #expect(version.stdout.contains(CapdKit.version))

            let help = try capd([], root: root)
            #expect(help.status == 0)
            #expect(help.stdout.contains("SUBCOMMANDS"))
        }
    }

    @Test("status reports before exiting 4 when no agent is running")
    func statusWithoutAgent() throws {
        try withScratchRoot { root in
            let status = try capd(["status"], root: root)
            #expect(status.status == 4)
            #expect(status.stdout.contains("Captures: 0"))
            #expect(status.stdout.contains("Queue: empty"))
            #expect(status.stdout.contains("Agent:"))
            #expect(status.stderr.contains("not running"))
        }
    }

    @Test("status --json carries counts, queue depth, and agent state")
    func statusJSON() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)
            _ = try capd(["add", "https://example.com/b"], root: root)

            let status = try capd(["status", "--json"], root: root)
            #expect(status.status == 4)

            let report = try jsonObject(status.stdout)
            let captures = try #require(report["captures"] as? [String: Any])
            #expect(captures["total"] as? Int == 2)
            #expect(captures["ok"] as? Int == 1)
            #expect(captures["pending"] as? Int == 1)

            let queue = try #require(report["queue"] as? [String: Any])
            #expect(queue["depth"] as? Int == 1)
            #expect((queue["eta_seconds"] as? Int ?? 0) > 0)

            let agent = try #require(report["agent"] as? [String: Any])
            #expect(agent["running"] as? Bool == false)
            #expect((report["database_bytes"] as? Int ?? 0) > 0)
        }
    }

    @Test("status exits 0 while a process holds the agent lock")
    func statusWithAgentLock() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let lockPath = StoragePaths(root: root).agentLockURL.path
            let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
            #expect(descriptor >= 0)
            defer { close(descriptor) }
            #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)

            let status = try capd(["status"], root: root)
            #expect(status.status == 0)
            #expect(status.stdout.contains("Agent: running"))
        }
    }

    @Test("doctor checks the store, rebuilds the index, and sweeps stale orphans")
    func doctorRepairsStore() throws {
        try withScratchRoot { root in
            _ = try capd(["add", "https://example.com/a", "--no-fetch"], root: root)

            let paths = StoragePaths(root: root)
            let orphan = paths.assetURL(forRelativePath: "bb/orphan.png")
            try FileManager.default.createDirectory(
                at: orphan.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: orphan)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -86_400)],
                ofItemAtPath: orphan.path)

            let doctor = try capd(["doctor", "--skip-agent"], root: root)
            #expect(doctor.status == 0)
            #expect(doctor.stdout.contains("Database: ok"))
            #expect(doctor.stdout.contains("Search index: rebuilt (1 capture)"))
            #expect(doctor.stdout.contains("Assets: removed 1 orphaned file"))
            #expect(doctor.stdout.contains("Accessibility:"))
            #expect(!FileManager.default.fileExists(atPath: orphan.path))
        }
    }

    @Test("doctor exits 1 when a capture's asset file is gone")
    func doctorReportsMissingAssets() throws {
        try withScratchRoot { root in
            let store = try Store(paths: StoragePaths(root: root))
            try store.dbPool.write { db in
                var broken = Capture(
                    kind: .image,
                    assetPath: "aa/gone.png",
                    enrichmentState: .ok,
                    createdAt: Date())
                try broken.insert(db)
            }

            let doctor = try capd(["doctor", "--skip-agent"], root: root)
            #expect(doctor.status == 1)
            #expect(doctor.stdout.contains("Assets: missing for capture #1"))
        }
    }
}
