import Foundation
import GRDB
import SQLite3

public enum StoreError: Error, Equatable {
    /// The file on disk was written by a newer build of cap than this one.
    case databaseIsNewerThanApp
}

extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseIsNewerThanApp:
            "The capture database was written by a newer version of cap."
        }
    }
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

    func updateNote(id: Int64, note: String?, now: Date = Date()) throws -> Capture {
        try dbPool.write { db in
            guard let current = try Capture.fetchOne(db, key: id) else {
                throw CaptureError.notFound(id)
            }
            var updated = current
            updated.note = note
            updated.updatedAt = now
            try updated.updateChanges(db, from: current)
            return updated
        }
    }

    /// Emits the number of captures whose enrichment failed, first immediately and then on
    /// every change, so the menu bar can badge without polling.
    public func failedEnrichmentCounts() -> AsyncValueObservation<Int> {
        ValueObservation
            .tracking { db in
                try Capture
                    .filter(Capture.CodingKeys.enrichmentState == EnrichmentState.failed)
                    .fetchCount(db)
            }
            .values(in: dbPool)
    }

    /// Removes captures and their content-addressed assets, returning what was deleted.
    ///
    /// Asset removal is best-effort: the rows are already gone, and a missing file must not
    /// resurrect them as an error.
    public func deleteCaptures(ids: [Int64]) throws -> [Capture] {
        let deleted = try dbPool.write { db in
            let doomed = try Capture.filter(ids.contains(Capture.CodingKeys.id)).fetchAll(db)
            try Capture.filter(ids.contains(Capture.CodingKeys.id)).deleteAll(db)
            return doomed
        }
        for capture in deleted {
            guard let assetPath = capture.assetPath else { continue }
            try? FileManager.default.removeItem(at: paths.assetURL(forRelativePath: assetPath))
        }
        return deleted
    }

    /// Puts the given captures back in the enrichment queue, returning how many moved.
    ///
    /// Any terminal row moves — requeueing an `ok` capture is a deliberate refresh. A
    /// `pending` row is already queued, and a `fetching` row belongs to whichever agent is
    /// mid-flight on it, so neither is touched.
    public func requeueCaptures(ids: [Int64]) throws -> Int {
        try requeue(
            Capture.filter(ids.contains(Capture.CodingKeys.id)),
            from: [.ok, .thin, .failed])
    }

    /// Requeues every capture whose enrichment ended badly.
    public func requeueFailedCaptures() throws -> Int {
        try requeue(Capture.all(), from: [.thin, .failed])
    }

    private func requeue(
        _ scope: QueryInterfaceRequest<Capture>,
        from states: [EnrichmentState]
    ) throws -> Int {
        try dbPool.write { db in
            try scope
                .filter(states.map(\.rawValue).contains(Capture.CodingKeys.enrichmentState))
                .updateAll(
                    db,
                    Capture.CodingKeys.enrichmentState.set(to: EnrichmentState.pending),
                    // Reset, or a capture that already burned its retries would requeue
                    // straight back to failed.
                    Capture.CodingKeys.attemptCount.set(to: 0),
                    Capture.CodingKeys.updatedAt.set(to: Date()))
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
