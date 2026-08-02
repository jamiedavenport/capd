import Foundation
import GRDB

extension Store {
    /// The `WHERE` guard is the claim: of the processes sharing this file, only the one
    /// that flips `pending` to `fetching` may enrich the row.
    func claimForEnrichment(id: Int64, now: Date = Date()) throws -> Capture? {
        try dbPool.write { db in
            try claim(db, id: id, now: now)
        }
    }

    /// Claims the oldest pending capture, so a draining process works in capture order.
    func claimNextForEnrichment(now: Date = Date()) throws -> Capture? {
        try dbPool.write { db in
            let id = try Int64.fetchOne(
                db,
                sql: """
                    SELECT id FROM \(Schema.captures)
                    WHERE enrichment_state = ?
                    ORDER BY id LIMIT 1
                    """,
                arguments: [EnrichmentState.pending.rawValue])
            guard let id else { return nil }
            return try claim(db, id: id, now: now)
        }
    }

    private func claim(_ db: Database, id: Int64, now: Date) throws -> Capture? {
        try db.execute(
            sql: """
                UPDATE \(Schema.captures)
                SET enrichment_state = :fetching,
                    attempt_count = attempt_count + 1,
                    last_attempt_at = :now,
                    updated_at = :now
                WHERE id = :id AND enrichment_state = :pending
                """,
            arguments: [
                "fetching": EnrichmentState.fetching.rawValue,
                "pending": EnrichmentState.pending.rawValue,
                "now": now,
                "id": id,
            ])
        guard db.changesCount == 1 else { return nil }
        return try Capture.fetchOne(db, key: id)
    }

    /// A nil field in `result` leaves its columns alone; the body columns move together
    /// because an extraction outcome is one fact, not three.
    func completeEnrichment(
        id: Int64,
        result: StepResult,
        state: EnrichmentState,
        now: Date = Date()
    ) throws -> Capture {
        try dbPool.write { db in
            guard let current = try Capture.fetchOne(db, key: id) else {
                throw EnrichmentError.captureNotFound(id)
            }
            guard current.enrichmentState.canTransition(to: state) else {
                throw EnrichmentError.illegalTransition(from: current.enrichmentState, to: state)
            }

            var updated = current
            if let ocrText = result.ocrText {
                updated.ocrText = ocrText
            }
            if let extraction = result.bodyExtraction {
                updated.body = extraction.body
                updated.bodyStatus = extraction.status
                updated.bodySource = extraction.source
                // Fills a hole, never overwrites: a title from capture time or the user
                // beats one scraped out of the page.
                if updated.title == nil {
                    updated.title = extraction.title
                }
            }
            updated.enrichmentState = state
            updated.updatedAt = now
            try updated.updateChanges(db, from: current)
            return updated
        }
    }

    /// Returns `fetching` rows claimed before `cutoff` (all of them when nil) to the
    /// queue, or to `failed` once `maxAttempts` claims have been spent on them.
    func reclaimStaleEnrichments(
        before cutoff: Date?,
        maxAttempts: Int,
        now: Date = Date()
    ) throws -> Int {
        let stale = try reader.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM \(Schema.captures)
                    WHERE enrichment_state = :fetching
                        AND (:cutoff IS NULL OR last_attempt_at <= :cutoff)
                    """,
                arguments: [
                    "fetching": EnrichmentState.fetching.rawValue,
                    "cutoff": cutoff,
                ]) ?? 0
        }
        guard stale > 0 else { return 0 }

        return try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE \(Schema.captures)
                    SET enrichment_state = CASE
                            WHEN attempt_count >= :maxAttempts THEN :failed
                            ELSE :pending
                        END,
                        updated_at = :now
                    WHERE enrichment_state = :fetching
                        AND (:cutoff IS NULL OR last_attempt_at <= :cutoff)
                    """,
                arguments: [
                    "maxAttempts": maxAttempts,
                    "failed": EnrichmentState.failed.rawValue,
                    "pending": EnrichmentState.pending.rawValue,
                    "fetching": EnrichmentState.fetching.rawValue,
                    "cutoff": cutoff,
                    "now": now,
                ])
            return db.changesCount
        }
    }

    func pendingEnrichmentCount() throws -> Int {
        try reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(Schema.captures) WHERE enrichment_state = ?",
                arguments: [EnrichmentState.pending.rawValue]) ?? 0
        }
    }
}
