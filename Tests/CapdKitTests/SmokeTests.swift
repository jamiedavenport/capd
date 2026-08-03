import GRDB
import Testing

@testable import CapdKit

@Suite("CapdKit smoke")
struct SmokeTests {
    @Test("CapdKit exposes a version")
    func versionIsPresent() {
        #expect(!CapdKit.version.isEmpty)
        #expect(CapdKit.bundleIdentifier == "dev.jxd.capd")
    }

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
