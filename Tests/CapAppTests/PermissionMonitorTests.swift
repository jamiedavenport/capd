import Testing

@testable import CapApp

@MainActor
@Suite("Permission monitor")
struct PermissionMonitorTests {
    @Test("A fresh grant is recorded and nothing is flagged")
    func recordsGrant() {
        let harness = Harness()
        harness.trusted = true

        harness.monitor.check()

        #expect(harness.grantedBefore)
        #expect(!harness.monitor.axLost)
        #expect(harness.losses == 0)
    }

    @Test("Never granted stays quiet — onboarding owns the first ask")
    func neverGrantedStaysQuiet() {
        let harness = Harness()

        harness.monitor.check()

        #expect(!harness.monitor.axLost)
        #expect(harness.losses == 0)
        #expect(!harness.grantedBefore)
    }

    @Test("Previously granted, now untrusted flags the loss and prompts once")
    func detectsLoss() {
        let harness = Harness()
        harness.grantedBefore = true

        harness.monitor.check()
        #expect(harness.monitor.axLost)
        #expect(harness.losses == 1)

        harness.monitor.check()
        #expect(harness.losses == 1)
    }

    @Test("Re-granting clears the degraded state and keeps the record")
    func recoversOnReGrant() {
        let harness = Harness()
        harness.grantedBefore = true
        harness.monitor.check()

        harness.trusted = true
        harness.monitor.check()

        #expect(!harness.monitor.axLost)
        #expect(harness.grantedBefore)

        harness.trusted = false
        harness.monitor.check()
        #expect(harness.monitor.axLost)
        #expect(harness.losses == 2)
    }

    @Test("Opening settings pokes the deep link")
    func opensSettings() {
        let harness = Harness()
        harness.monitor.openAccessibilitySettings()
        #expect(harness.settingsOpens == 1)
    }
}

/// A monitor wired to stub trust and persistence state.
@MainActor
private final class Harness {
    var trusted = false
    var grantedBefore = false
    var settingsOpens = 0
    var losses = 0

    private(set) lazy var monitor: PermissionMonitor = {
        let monitor = PermissionMonitor(
            environment: PermissionMonitorEnvironment(
                isAXTrusted: { [unowned self] in trusted },
                wasGrantedBefore: { [unowned self] in grantedBefore },
                setWasGrantedBefore: { [unowned self] in grantedBefore = $0 },
                openAXSettings: { [unowned self] in settingsOpens += 1 }))
        monitor.onLoss = { [unowned self] in losses += 1 }
        return monitor
    }()
}
