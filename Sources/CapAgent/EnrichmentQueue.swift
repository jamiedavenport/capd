import CapKit
import Foundation

/// Drains pending captures with bounded parallelism.
actor EnrichmentQueue {
    private let enrichment: EnrichmentService
    private let isOnMainsPower: @Sendable () -> Bool
    private var draining = false

    init(enrichment: EnrichmentService, isOnMainsPower: @escaping @Sendable () -> Bool) {
        self.enrichment = enrichment
        self.isOnMainsPower = isOnMainsPower
    }

    /// Processes captures until none are pending: at most three concurrently on mains
    /// power, one on battery, decided once per drain. A call while a drain is already
    /// running returns immediately — the running workers claim until the queue is empty,
    /// so they pick up whatever the caller saw.
    func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        let width = DrainPolicy.width(onMainsPower: isOnMainsPower())
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<width {
                group.addTask { [enrichment] in
                    do {
                        while try await enrichment.processNext() != nil {}
                    } catch {
                        // The service already recorded the failure on the row; the rest
                        // of the queue waits for the next drain rather than risking a spin.
                    }
                }
            }
        }
    }
}
