import Foundation
import Testing

@testable import CapdApp

@Suite("Context reminder policy")
struct ContextReminderPolicyTests {
    @Test("A stable page becomes eligible after the dwell time")
    func dwell() throws {
        var policy = ContextReminderPolicy(dwellTime: 2)
        let url = try #require(URL(string: "https://example.com/article"))
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(policy.observe(url, now: start) == .none)
        #expect(policy.observe(url, now: start.addingTimeInterval(1.9)) == .none)
        guard
            case .lookUp(let observation) =
                policy.observe(url, now: start.addingTimeInterval(2))
        else {
            Issue.record("expected a lookup after the dwell time")
            return
        }
        #expect(observation.url == url)
    }

    @Test("A page is handled only once per session")
    func oncePerSession() throws {
        var policy = ContextReminderPolicy(dwellTime: 0)
        let url = try #require(URL(string: "https://example.com/article"))
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(policy.observe(url, now: now) == .none)
        guard case .lookUp = policy.observe(url, now: now) else {
            Issue.record("expected the first lookup")
            return
        }
        policy.suspend()
        #expect(policy.observe(url, now: now) == .none)
        #expect(policy.observe(url, now: now.addingTimeInterval(10)) == .none)
    }

    @Test("Changing pages restarts the dwell time")
    func navigationRestartsDwell() throws {
        var policy = ContextReminderPolicy(dwellTime: 2)
        let first = try #require(URL(string: "https://example.com/first"))
        let second = try #require(URL(string: "https://example.com/second"))
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        _ = policy.observe(first, now: start)
        _ = policy.observe(second, now: start.addingTimeInterval(1.5))

        #expect(policy.observe(second, now: start.addingTimeInterval(3)) == .none)
        guard case .lookUp = policy.observe(second, now: start.addingTimeInterval(3.5)) else {
            Issue.record("expected the second page after its own dwell time")
            return
        }
    }

    @Test("Capd-attributed pages are suppressed before normalization")
    func attributedPageIsSuppressed() throws {
        var policy = ContextReminderPolicy(dwellTime: 0)
        let url = try #require(
            URL(string: "https://example.com/article?utm_source=capd.jxd.dev&utm_medium=app"))
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(policy.observe(url, now: now) == .none)
        #expect(policy.observe(url, now: now.addingTimeInterval(10)) == .none)
    }

    @Test("A local suppression marks a page handled even after attribution disappears")
    func localSuppressionSurvivesCleanURL() throws {
        var policy = ContextReminderPolicy(dwellTime: 0)
        let url = try #require(URL(string: "https://example.com/article"))
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(policy.observe(url, externallySuppressed: true, now: now) == .none)
        #expect(policy.observe(url, now: now.addingTimeInterval(10)) == .none)
    }
}
