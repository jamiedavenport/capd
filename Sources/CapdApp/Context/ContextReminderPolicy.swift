import CapdKit
import Foundation

struct ContextReminderPolicy: Equatable {
    enum Action: Equatable {
        case none
        case lookUp(ContextObservation)
    }

    private struct Candidate: Equatable {
        var observation: ContextObservation
        var firstObservedAt: Date
    }

    var dwellTime: TimeInterval = 2
    private(set) var currentIdentity: String?
    private var candidate: Candidate?
    private var handled: Set<String> = []

    init(dwellTime: TimeInterval = 2) {
        self.dwellTime = dwellTime
    }

    mutating func observe(
        _ url: URL?, externallySuppressed: Bool = false, now: Date = Date()
    ) -> Action {
        guard let url, let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            suspend()
            return .none
        }

        let observation = ContextObservation(url: url, identity: URLNormalizer.normalize(url))
        currentIdentity = observation.identity

        if externallySuppressed || CapdLinkAttribution.isAttributed(url) {
            handled.insert(observation.identity)
            candidate = nil
            return .none
        }
        if handled.contains(observation.identity) {
            candidate = nil
            return .none
        }
        guard candidate?.observation.identity == observation.identity else {
            candidate = Candidate(observation: observation, firstObservedAt: now)
            return .none
        }
        guard let candidate, now.timeIntervalSince(candidate.firstObservedAt) >= dwellTime else {
            return .none
        }

        handled.insert(observation.identity)
        self.candidate = nil
        return .lookUp(observation)
    }

    mutating func suspend() {
        currentIdentity = nil
        candidate = nil
    }

    func isCurrent(_ observation: ContextObservation) -> Bool {
        currentIdentity == observation.identity
    }
}
