import Foundation

/// Runs every applicable step over one claimed capture and writes the outcome.
///
/// The runner, not the steps, owns the state machine: there is no legal path from
/// `pending` straight to `ok`, and steps stay pure so they never need write access.
public struct EnrichmentRunner: Sendable {
    let store: Store
    let steps: [any ProcessingStep]

    public init(store: Store, steps: [any ProcessingStep]) {
        self.store = store
        self.steps = steps
    }

    /// Returns nil when the capture is absent or not pending, so racing processes
    /// produce one winner and the losers treat it as a no-op.
    @discardableResult
    public func process(captureID: Int64) async throws -> Capture? {
        guard let claimed = try store.claimForEnrichment(id: captureID) else {
            return nil
        }

        let context = ProcessingContext(paths: store.paths)
        var merged = StepResult()
        do {
            for step in steps where step.applies(to: claimed) {
                let result = try await step.run(claimed, context: context)
                if let ocrText = result.ocrText {
                    merged.ocrText = ocrText
                }
            }
        } catch {
            // The failure is recorded before rethrowing so the row never sticks in fetching.
            _ = try store.completeEnrichment(id: captureID, ocrText: nil, state: .failed)
            throw error
        }

        return try store.completeEnrichment(id: captureID, ocrText: merged.ocrText, state: .ok)
    }
}
