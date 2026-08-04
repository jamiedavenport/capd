import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("Ambient context monitor")
struct AmbientContextMonitorTests {
    @Test("A stable saved browser page presents its insight")
    func presentsInsight() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let capture = Capture(
            id: 1,
            kind: .link,
            url: url.absoluteString,
            host: "example.com",
            createdAt: Date(timeIntervalSinceReferenceDate: 500))
        let insight = ContextInsight(kind: .previouslySaved, capture: capture)
        var presented: [ContextInsight] = []
        let monitor = AmbientContextMonitor(
            environment: AmbientContextEnvironment(
                isSecureInputActive: { false },
                frontmostTarget: {
                    FrontmostTarget(
                        bundleID: Browser.safari.rawValue,
                        name: "Safari",
                        processIdentifier: 1)
                },
                browserTab: { _, _ in BrowserTab(url: url.absoluteString) },
                isSuppressed: { _ in false },
                insight: { _ in insight },
                present: { presented.append($0) },
                now: { Date(timeIntervalSinceReferenceDate: 1_000) }),
            policy: ContextReminderPolicy(dwellTime: 0))

        await monitor.poll()
        await monitor.poll()

        #expect(presented == [insight])
    }

    @Test("A capture completed during lookup does not replace the capture HUD")
    func captureDuringLookupSuppressesInsight() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let capture = Capture(
            id: 1,
            kind: .link,
            url: url.absoluteString,
            host: "example.com",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let insight = ContextInsight(kind: .previouslySaved, capture: capture)
        let suppressions = ContextSuppressionRegistry()
        var presented: [ContextInsight] = []
        let monitor = AmbientContextMonitor(
            environment: AmbientContextEnvironment(
                isSecureInputActive: { false },
                frontmostTarget: {
                    FrontmostTarget(
                        bundleID: Browser.safari.rawValue,
                        name: "Safari",
                        processIdentifier: 1)
                },
                browserTab: { _, _ in BrowserTab(url: url.absoluteString) },
                isSuppressed: { suppressions.contains($0) },
                insight: { _ in
                    await MainActor.run { suppressions.register(capture: capture) }
                    return insight
                },
                present: { presented.append($0) },
                now: { Date(timeIntervalSinceReferenceDate: 1_000) }),
            policy: ContextReminderPolicy(dwellTime: 0))

        await monitor.poll()
        await monitor.poll()

        #expect(presented.isEmpty)
    }

    @Test("Secure input prevents browser observation")
    func secureInputStopsObservation() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        var browserReads = 0
        var presented: [ContextInsight] = []
        let monitor = AmbientContextMonitor(
            environment: AmbientContextEnvironment(
                isSecureInputActive: { true },
                frontmostTarget: {
                    FrontmostTarget(
                        bundleID: Browser.safari.rawValue,
                        name: "Safari",
                        processIdentifier: 1)
                },
                browserTab: { _, _ in
                    browserReads += 1
                    return BrowserTab(url: url.absoluteString)
                },
                isSuppressed: { _ in false },
                insight: { _ in nil },
                present: { presented.append($0) },
                now: Date.init))

        await monitor.poll()

        #expect(browserReads == 0)
        #expect(presented.isEmpty)
    }
}
