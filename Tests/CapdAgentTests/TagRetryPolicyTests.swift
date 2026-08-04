import Foundation
import Testing

@testable import CapdAgent

@Suite("Tag retry policy")
struct TagRetryPolicyTests {
    @Test("Transient failures back off exponentially and cap at five minutes")
    func exponentialBackoff() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = TagRetryPolicy()
        var now = start
        var delays: [TimeInterval] = []

        for _ in 0..<7 {
            let delay = policy.recordFailure(at: now)
            delays.append(delay)
            #expect(!policy.shouldAttempt(at: now))
            now = now.addingTimeInterval(delay)
            #expect(policy.shouldAttempt(at: now))
        }

        #expect(delays == [15, 30, 60, 120, 240, 300, 300])
    }

    @Test("A successful attempt clears the backoff")
    func successResetsBackoff() {
        let now = Date(timeIntervalSince1970: 1_000)
        var policy = TagRetryPolicy()
        _ = policy.recordFailure(at: now)

        policy.recordSuccess()

        #expect(policy.failureCount == 0)
        #expect(policy.nextAttemptAt == nil)
        #expect(policy.shouldAttempt(at: now))
        #expect(policy.recordFailure(at: now) == TagRetryPolicy.initialDelay)
    }
}
