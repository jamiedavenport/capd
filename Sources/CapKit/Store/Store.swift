import Foundation
import GRDB
import SQLite3

public enum StoreError: Error, Equatable {
    /// The file on disk was written by a newer build of cap than this one.
    case databaseIsNewerThanApp
}

enum EnrichmentError: Error, Equatable {
    case captureNotFound(Int64)
    case illegalTransition(from: EnrichmentState, to: EnrichmentState)
}

/// The database every cap process shares.
///
/// The menu-bar app, `cap-agent`, and the `cap` CLI are three unsandboxed processes on one
/// file, so this opens in WAL mode with a busy timeout rather than assuming sole ownership.
public final class Store: Sendable {
    public let paths: StoragePaths

    let dbPool: DatabasePool

    /// Reads are public; writes stay internal so every capture goes through the one service
    /// that applies the capture guards.
    public var reader: any DatabaseReader { dbPool }

    public init(paths: StoragePaths) throws {
        self.paths = paths
        try paths.createDirectories()
        dbPool = try Self.openCoordinated(at: paths.databaseURL)
    }

    /// The hash check shares the write transaction rather than relying on the unique index,
    /// so the choice between inserting and merging is atomic across the three processes.
    func upsertCapture(_ capture: Capture) throws -> CaptureOutcome {
        try dbPool.write { db in
            if let hash = capture.contentHash,
                var existing = try Capture.filter(Capture.CodingKeys.contentHash == hash)
                    .fetchOne(db)
            {
                let previousSeenAt = existing.lastSeenAt
                existing.seenCount += 1
                existing.lastSeenAt = capture.createdAt
                existing.updatedAt = capture.createdAt
                existing.title = existing.title ?? capture.title
                existing.note = existing.note ?? capture.note
                existing.selection = existing.selection ?? capture.selection

                // An incoming `.pending` means this request wants enrichment; a broken row is
                // repaired by re-queueing it, but a healthy one is left alone.
                if capture.enrichmentState == .pending,
                    existing.enrichmentState == .failed || existing.enrichmentState == .thin
                {
                    existing.enrichmentState = .pending
                    existing.attemptCount = 0
                    existing.lastAttemptAt = nil
                }

                try existing.update(db)
                return .alreadyCaptured(existing, previousSeenAt: previousSeenAt)
            }

            var inserted = capture
            try inserted.insert(db)
            return .captured(inserted)
        }
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
