import Foundation
import GRDB

public struct AssetSweep: Sendable, Equatable {
    /// Files removed from the assets directory, relative paths.
    public let removedPaths: [String]
    /// Captures whose `asset_path` no longer resolves to a file.
    public let missingCaptureIDs: [Int64]
}

extension Store {
    public func enrichmentCounts() throws -> [EnrichmentState: Int] {
        let rows = try reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT enrichment_state, COUNT(*) AS count
                    FROM \(Schema.captures)
                    GROUP BY enrichment_state
                    """)
        }
        return rows.reduce(into: [:]) { counts, row in
            guard let state = EnrichmentState(rawValue: row["enrichment_state"]) else { return }
            counts[state] = row["count"]
        }
    }

    /// Mean wall-clock seconds of the most recent completed enrichments, or nil before
    /// any capture has been through the pipeline. Feeds the `cap status` ETA.
    public func averageEnrichmentSeconds(over sample: Int = 50) throws -> Double? {
        try reader.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT AVG(seconds) FROM (
                        SELECT (julianday(updated_at) - julianday(last_attempt_at)) * 86400.0
                            AS seconds
                        FROM \(Schema.captures)
                        WHERE enrichment_state IN (:ok, :thin, :failed)
                            AND last_attempt_at IS NOT NULL
                        ORDER BY updated_at DESC
                        LIMIT :sample
                    )
                    WHERE seconds >= 0
                    """,
                arguments: [
                    "ok": EnrichmentState.ok.rawValue,
                    "thin": EnrichmentState.thin.rawValue,
                    "failed": EnrichmentState.failed.rawValue,
                    "sample": sample,
                ])
        }
    }

    /// On-disk size of the database, WAL included — what the user would measure.
    public func databaseBytes() -> Int64 {
        let base = paths.databaseURL.path
        return [base, base + "-wal", base + "-shm"].reduce(into: Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size]
            total += (size as? Int64) ?? 0
        }
    }

    /// `PRAGMA integrity_check` verbatim: `["ok"]` when the file is sound.
    public func checkIntegrity() throws -> [String] {
        try reader.read { db in
            try String.fetchAll(db, sql: "PRAGMA integrity_check")
        }
    }

    /// Rebuilds the FTS index from the captures table, returning how many rows it now
    /// covers.
    public func rebuildSearchIndex() throws -> Int {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO \(Schema.capturesFTS)(\(Schema.capturesFTS)) VALUES('rebuild')")
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(Schema.captures)") ?? 0
        }
    }

    /// Deletes asset files no capture references, and reports captures whose asset file
    /// is gone. Files newer than `unusedFor` are spared: an asset is written to disk
    /// before its row is inserted, so a young unreferenced file may be mid-ingest.
    public func sweepOrphanAssets(
        unusedFor grace: TimeInterval = 3600,
        now: Date = Date()
    ) throws -> AssetSweep {
        let references = try reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, asset_path FROM \(Schema.captures)
                    WHERE asset_path IS NOT NULL
                    """)
        }
        let referenced = Set(references.map { $0["asset_path"] as String })

        let fileManager = FileManager.default
        let root = paths.assetsDirectory.resolvingSymlinksInPath()
        var removed: [String] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: Array(keys))
        while let entry = enumerator?.nextObject() as? URL {
            let url = entry.resolvingSymlinksInPath()
            guard let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard !referenced.contains(relative) else { continue }
            if let modified = values.contentModificationDate,
                now.timeIntervalSince(modified) < grace
            {
                continue
            }
            try fileManager.removeItem(at: url)
            removed.append(relative)
        }

        let missing = references.compactMap { row -> Int64? in
            let path: String = row["asset_path"]
            let url = paths.assetURL(forRelativePath: path)
            return fileManager.fileExists(atPath: url.path) ? nil : row["id"]
        }

        return AssetSweep(removedPaths: removed.sorted(), missingCaptureIDs: missing.sorted())
    }
}
