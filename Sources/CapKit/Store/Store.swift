import Foundation
import GRDB
import SQLite3

public enum StoreError: Error, Equatable {
    /// The file on disk was written by a newer build of cap than this one.
    case databaseIsNewerThanApp
}

/// The database every cap process shares.
///
/// The menu-bar app, `cap-agent`, and the `cap` CLI are three unsandboxed processes on one
/// file, so this opens in WAL mode with a busy timeout rather than assuming sole ownership.
///
/// Enrichment moves a row through ``EnrichmentState`` — diagrammed on that type — while
/// ``BodyStatus`` records what body extraction produced. For a link capture the two agree: a
/// thin body leaves the row `thin`. They part company everywhere else. An image capture is
/// enriched by OCR and keeps `bodyStatus == .none`; a link captured with `--no-fetch` is born
/// terminal without entering the queue at all. The agent's queue selects on `enrichment_state`;
/// `cap refetch` selects on `body_status`.
public final class Store: Sendable {
    public let paths: StoragePaths

    let dbPool: DatabasePool

    /// Read access for search and the CLI. Writes stay internal to CapKit so that every
    /// capture goes through the one service that applies the capture guards.
    public var reader: any DatabaseReader { dbPool }

    public init(paths: StoragePaths) throws {
        self.paths = paths
        try paths.createDirectories()
        dbPool = try Self.openCoordinated(at: paths.databaseURL)
    }

    /// Opens under an `NSFileCoordinator` so that two processes racing to create the database
    /// on first launch don't both try to lay down the schema.
    private static func openCoordinated(at url: URL) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var result: Result<DatabasePool, any Error>?

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) {
            url in
            result = Result { try open(at: url) }
        }

        if let coordinatorError, result == nil {
            throw coordinatorError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    private static func open(at url: URL) throws -> DatabasePool {
        var configuration = Configuration()

        // GRDB defaults to failing immediately on a locked database, which for three processes
        // sharing one file means the CLI errors whenever the agent happens to be draining.
        configuration.busyMode = .timeout(5)

        configuration.prepareDatabase { db in
            guard !db.configuration.readonly else { return }
            // Without this, SQLite deletes the -wal and -shm files when the last connection
            // closes, and a read-only process can no longer open the database at all.
            var flag: CInt = 1
            let code = withUnsafeMutablePointer(to: &flag) { pointer in
                sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, pointer)
            }
            guard code == SQLITE_OK else {
                throw DatabaseError(resultCode: ResultCode(rawValue: code))
            }
        }

        let dbPool = try DatabasePool(path: url.path, configuration: configuration)
        let migrator = Migrations.migrator
        try migrator.migrate(dbPool)

        if try dbPool.read(migrator.hasBeenSuperseded) {
            throw StoreError.databaseIsNewerThanApp
        }

        return dbPool
    }
}
