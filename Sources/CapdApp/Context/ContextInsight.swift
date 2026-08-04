import CapdKit
import Foundation

struct ContextObservation: Equatable, Sendable {
    var url: URL
    var identity: String
}

struct ContextInsight: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case previouslySaved
    }

    var kind: Kind
    var capture: Capture
}

protocol ContextInsightProvider: Sendable {
    func insight(for observation: ContextObservation) async throws -> ContextInsight?
}

struct PreviouslySavedInsightProvider: ContextInsightProvider {
    var findCapture: @Sendable (URL) throws -> Capture?

    func insight(for observation: ContextObservation) async throws -> ContextInsight? {
        guard let capture = try findCapture(observation.url) else { return nil }
        return ContextInsight(kind: .previouslySaved, capture: capture)
    }
}

struct ContextInsightEngine: Sendable {
    var providers: [any ContextInsightProvider]

    func insight(for observation: ContextObservation) async -> ContextInsight? {
        for provider in providers {
            if let insight = try? await provider.insight(for: observation) {
                return insight
            }
        }
        return nil
    }
}
