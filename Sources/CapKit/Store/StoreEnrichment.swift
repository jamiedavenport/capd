import Foundation
import GRDB

extension Store {
    func applyExtraction(
        id: Int64,
        body: String?,
        bodyStatus: BodyStatus,
        bodySource: BodySource,
        enrichmentState: EnrichmentState,
        now: Date = Date()
    ) throws -> Capture {
        try dbPool.write { db in
            guard let current = try Capture.fetchOne(db, key: id) else {
                throw EnrichmentError.captureNotFound(id)
            }
            guard current.enrichmentState.canTransition(to: enrichmentState) else {
                throw EnrichmentError.illegalTransition(
                    from: current.enrichmentState, to: enrichmentState)
            }

            var updated = current
            updated.body = body
            updated.bodyStatus = bodyStatus
            updated.bodySource = bodySource
            updated.enrichmentState = enrichmentState
            updated.updatedAt = now
            try updated.updateChanges(db, from: current)
            return updated
        }
    }
}
