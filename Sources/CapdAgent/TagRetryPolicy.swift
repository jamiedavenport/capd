import Foundation

/// Exponential backoff for transient tagging failures. Terminal per-capture failures are
/// consumed by `TagService` and never reach this policy.
struct TagRetryPolicy {
    static let initialDelay: TimeInterval = 15
    static let maximumDelay: TimeInterval = 5 * 60

    private(set) var failureCount = 0
    private(set) var nextAttemptAt: Date?

    func shouldAttempt(at now: Date = Date()) -> Bool {
        guard let nextAttemptAt else { return true }
        return now >= nextAttemptAt
    }

    mutating func recordSuccess() {
        failureCount = 0
        nextAttemptAt = nil
    }

    @discardableResult
    mutating func recordFailure(at now: Date = Date()) -> TimeInterval {
        let exponent = min(failureCount, 5)
        let delay = min(Self.initialDelay * Double(1 << exponent), Self.maximumDelay)
        failureCount += 1
        nextAttemptAt = now.addingTimeInterval(delay)
        return delay
    }
}
