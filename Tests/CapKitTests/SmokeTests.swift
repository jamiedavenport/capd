import GRDB
import Testing

@testable import CapKit

/// Scaffold-level smoke tests. Their job is to fail loudly if the toolchain, the
/// language mode, or a dependency is broken — not to test behaviour that does not
/// exist yet.
@Suite("CapKit smoke")
struct SmokeTests {
    @Test("CapKit exposes a version")
    func versionIsPresent() {
        #expect(!CapKit.version.isEmpty)
        #expect(CapKit.bundleIdentifier == "dev.jxd.cap")
    }

    /// Proves GRDB and its bundled SQLite link and work under Swift 6 strict
    /// concurrency. This is the foundation the real store and migrations (T1)
    /// are built on, so it is worth catching a linking problem here.
    @Test("GRDB opens a database and round-trips a row")
    func databaseRoundTrip() throws {
        let queue = try DatabaseQueue()

        try queue.write { db in
            try db.execute(
                sql: "CREATE TABLE smoke (id INTEGER PRIMARY KEY, note TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO smoke (note) VALUES (?)", arguments: ["hello"])
        }

        let note = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT note FROM smoke")
        }

        #expect(note == "hello")
    }
}
