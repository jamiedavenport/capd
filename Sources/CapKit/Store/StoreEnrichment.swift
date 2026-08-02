import Foundation
import GRDB

extension Store {
    /// The check-and-set shares one write transaction, which under WAL makes it the claim:
    /// of two processes racing for a pending row, the loser reads `fetching` and is refused.
    func claimForEnrichment(id: Int64, at date: Date) throws -> Capture {
        try dbPool.write { db in
            guard var capture = try Capture.fetchOne(db, key: id) else {
                throw EnrichmentError.captureNotFound(id)
            }
            guard capture.enrichmentState.canTransition(to: .fetching) else {
                throw EnrichmentError.notClaimable(capture.enrichmentState)
            }
            capture.enrichmentState = .fetching
            capture.attemptCount += 1
            capture.lastAttemptAt = date
            capture.updatedAt = date
            try capture.update(db)
            return capture
        }
    }

    func applyExtraction(
        id: Int64,
        body: String?,
        bodyStatus: BodyStatus,
        bodySource: BodySource,
        enrichmentState: EnrichmentState,
        at date: Date
    ) throws -> Capture {
        try dbPool.write { db in
            guard var capture = try Capture.fetchOne(db, key: id) else {
                throw EnrichmentError.captureNotFound(id)
            }
            guard capture.enrichmentState.canTransition(to: enrichmentState) else {
                throw EnrichmentError.illegalTransition(
                    from: capture.enrichmentState, to: enrichmentState)
            }
            capture.body = body
            capture.bodyStatus = bodyStatus
            capture.bodySource = bodySource
            capture.enrichmentState = enrichmentState
            capture.updatedAt = date
            try capture.update(db)
            return capture
        }
    }
}
