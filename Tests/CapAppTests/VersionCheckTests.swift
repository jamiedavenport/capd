import CapKit
import Foundation
import Testing

@testable import CapApp
@testable import CapAppUI

@MainActor
@Suite("Version check")
struct VersionCheckTests {
    @Test("A newer released tag surfaces an available update")
    func newerTagSurfacesUpdate() async throws {
        let harness = Harness(tag: "v999.0.0")

        await harness.checker.checkIfDue()

        #expect(harness.requestCount == 1)
        #expect(harness.checker.availableVersion == "v999.0.0")
    }

    @Test("The running version stays quiet")
    func runningVersionStaysQuiet() async throws {
        let harness = Harness(tag: "v\(CapKit.version)")

        await harness.checker.checkIfDue()

        #expect(harness.checker.availableVersion == nil)
    }

    @Test("Toggled off, no request is made")
    func toggledOffMakesNoRequest() async throws {
        let harness = Harness(tag: "v999.0.0")
        harness.settings.checksForUpdates = false

        await harness.checker.checkIfDue()

        #expect(harness.requestCount == 0)
        #expect(harness.checker.availableVersion == nil)
    }

    @Test("A second check within the week is skipped")
    func withinWeekSkips() async throws {
        let harness = Harness(tag: "v999.0.0")

        await harness.checker.checkIfDue()
        harness.advance(by: 3 * 24 * 60 * 60)
        await harness.checker.checkIfDue()

        #expect(harness.requestCount == 1)
    }

    @Test("A check after a week fetches again")
    func afterWeekRefetches() async throws {
        let harness = Harness(tag: "v999.0.0")

        await harness.checker.checkIfDue()
        harness.advance(by: 8 * 24 * 60 * 60)
        await harness.checker.checkIfDue()

        #expect(harness.requestCount == 2)
    }

    @Test("A failed request retries on the next pass")
    func failureRetriesNextPass() async throws {
        let harness = Harness(tag: "v999.0.0")
        harness.fails = true

        await harness.checker.checkIfDue()
        #expect(harness.checker.availableVersion == nil)

        harness.fails = false
        await harness.checker.checkIfDue()

        #expect(harness.requestCount == 2)
        #expect(harness.checker.availableVersion == "v999.0.0")
    }

    @Test("A found update survives a relaunch")
    func updateSurvivesRelaunch() async throws {
        let harness = Harness(tag: "v999.0.0")
        await harness.checker.checkIfDue()

        let relaunched = UpdateChecker(
            settings: AppSettings(defaults: harness.defaults),
            client: ReleaseClient { throw URLError(.notConnectedToInternet) })

        #expect(relaunched.availableVersion == "v999.0.0")
    }

    @Test("Settings persist across relaunches")
    func settingsPersist() throws {
        let harness = Harness(tag: "v999.0.0")
        harness.settings.fetchesPageBodies = false
        harness.settings.checksForUpdates = false

        let relaunched = AppSettings(defaults: harness.defaults)

        #expect(relaunched.fetchesPageBodies == false)
        #expect(relaunched.checksForUpdates == false)
    }

    @Test(
        "Release tags order numerically",
        arguments: [
            (tag: "v0.2.0", current: "0.0.1", newer: true),
            (tag: "0.10.0", current: "0.9.9", newer: true),
            (tag: "v1.0.1", current: "1.0", newer: true),
            (tag: "v1.0.0", current: "1.0.0", newer: false),
            (tag: "v1.0", current: "1.0.0", newer: false),
            (tag: "v0.0.1", current: "0.0.2", newer: false),
            (tag: "v0.2.0-beta", current: "0.2.0", newer: false),
            (tag: "nonsense", current: "0.0.1", newer: false),
        ])
    func tagsOrderNumerically(_ example: (tag: String, current: String, newer: Bool)) {
        #expect(ReleaseVersion.isNewer(tag: example.tag, than: example.current) == example.newer)
    }
}

/// An `UpdateChecker` wired to a counting stub client, a controllable clock, and a
/// throwaway defaults suite.
@MainActor
private final class Harness {
    let defaults: UserDefaults
    let settings: AppSettings
    private(set) var checker: UpdateChecker!
    private(set) var requestCount = 0
    var fails = false

    private let suiteName = "dev.jxd.cap.tests.\(UUID().uuidString)"
    private var now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init(tag: String) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = AppSettings(defaults: defaults)
        checker = UpdateChecker(
            settings: settings,
            client: ReleaseClient { @MainActor [unowned self] in
                requestCount += 1
                if fails {
                    throw URLError(.notConnectedToInternet)
                }
                return tag
            },
            now: { [unowned self] in now })
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
