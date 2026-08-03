import Foundation
import KeyboardShortcuts
import Testing

@testable import CapApp
@testable import CapAppUI

@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
    @Test("Opening the flow installs the agent and starts on the hotkey step")
    func startsOnHotkeysAndInstallsAgent() {
        let harness = Harness()
        #expect(harness.model.step == .hotkeys)
        #expect(harness.installCalls == 1)
    }

    @Test("Steps advance in order and clamp at both ends")
    func stepNavigation() {
        let harness = Harness()
        let model = harness.model

        model.back()
        #expect(model.step == .hotkeys)

        model.advance()
        #expect(model.step == .accessibility)
        model.advance()
        #expect(model.step == .browsers)
        model.advance()
        #expect(model.step == .firstCapture)
        #expect(model.isLastStep)
        model.advance()
        #expect(model.step == .firstCapture)

        model.back()
        #expect(model.step == .browsers)
    }

    @Test("A hotkey taken by a macOS system shortcut is flagged")
    func conflictFlagged() {
        let harness = Harness()
        #expect(harness.model.conflicted.isEmpty)

        harness.taken = [.init(.space, modifiers: [.option, .shift])]
        harness.model.refresh()
        #expect(harness.model.conflicted == [.search])

        harness.taken = []
        harness.model.refresh()
        #expect(harness.model.conflicted.isEmpty)
    }

    @Test("The recorded shortcuts are displayed, and re-recording shows up on refresh")
    func shortcutDisplay() {
        let harness = Harness()
        #expect(harness.model.captureShortcut == harness.captureShortcut?.description)

        harness.searchShortcut = .init(.f, modifiers: [.command, .shift])
        harness.model.refresh()
        #expect(harness.model.searchShortcut == harness.searchShortcut?.description)
    }

    @Test("Permission and agent state surface on refresh")
    func refreshMirrorsState() {
        let harness = Harness()
        #expect(!harness.model.axTrusted)
        #expect(!harness.model.agentLoaded)

        harness.trusted = true
        harness.agentLoaded = true
        harness.model.refresh()

        #expect(harness.model.axTrusted)
        #expect(harness.model.agentLoaded)
    }

    @Test("Accessibility priming pokes the system prompt and the deep link")
    func accessibilityPriming() {
        let harness = Harness()
        harness.model.requestAccessibility()
        harness.model.openAccessibilitySettings()
        #expect(harness.axPrompts == 1)
        #expect(harness.axSettingsOpens == 1)
    }

    @Test("Only browsers with an Apple Events path appear, with their consent state")
    func browserConsents() async {
        let harness = Harness()
        harness.running = [.safari, .firefox, .chrome]
        harness.statuses = [.safari: .granted, .chrome: .undetermined]
        harness.model.refresh()

        #expect(harness.model.runningBrowsers == [.safari, .chrome])
        #expect(harness.model.consents[.safari] == .granted)
        #expect(harness.model.consents[.chrome] == .undetermined)

        harness.promptResult = .granted
        await harness.model.requestConsent(for: .chrome).value

        #expect(harness.prompted == [.chrome])
        #expect(harness.model.consents[.chrome] == .granted)
        #expect(harness.model.pendingConsents.isEmpty)
    }

    @Test("The guided first capture latches once a capture exists")
    func captureLatch() {
        let harness = Harness()
        #expect(!harness.model.hasCaptured)

        harness.captureCount = 1
        harness.model.refresh()
        #expect(harness.model.hasCaptured)

        harness.captureCount = 0
        harness.model.refresh()
        #expect(harness.model.hasCaptured)
    }

    @Test("Opening search completes the guided search")
    func searchLatch() {
        let harness = Harness()
        #expect(!harness.model.hasSearched)
        harness.model.noteSearchOpened()
        #expect(harness.model.hasSearched)
    }

    @Test("Finishing reports completion")
    func finishReports() {
        let harness = Harness()
        harness.model.finish()
        #expect(harness.finished == 1)
    }
}

/// A model wired to stub permissions, consent, and store state.
@MainActor
private final class Harness {
    var captureShortcut: KeyboardShortcuts.Shortcut? = .init(.c, modifiers: [.control, .option])
    var annotateShortcut: KeyboardShortcuts.Shortcut? = .init(.n, modifiers: [.control, .option])
    var searchShortcut: KeyboardShortcuts.Shortcut? = .init(.space, modifiers: [.option, .shift])
    var taken: [KeyboardShortcuts.Shortcut] = []
    var trusted = false
    var axPrompts = 0
    var axSettingsOpens = 0
    var automationSettingsOpens = 0
    var running: [Browser] = []
    var statuses: [Browser: AutomationConsentStatus] = [:]
    var prompted: [Browser] = []
    var promptResult: AutomationConsentStatus = .undetermined
    var captureCount = 0
    var installCalls = 0
    var agentLoaded = false
    var finished = 0

    private(set) lazy var model: OnboardingModel = {
        let model = OnboardingModel(
            environment: OnboardingEnvironment(
                shortcut: { [unowned self] name in
                    switch name {
                    case .capture: captureShortcut
                    case .annotate: annotateShortcut
                    default: searchShortcut
                    }
                },
                isShortcutTakenBySystem: { [unowned self] in taken.contains($0) },
                isAXTrusted: { [unowned self] in trusted },
                requestAXTrust: { [unowned self] in axPrompts += 1 },
                openAXSettings: { [unowned self] in axSettingsOpens += 1 },
                openAutomationSettings: { [unowned self] in automationSettingsOpens += 1 },
                runningBrowsers: { [unowned self] in running },
                automationStatus: { [unowned self] in statuses[$0] ?? .undetermined },
                requestAutomationConsent: { [unowned self] browser in
                    prompted.append(browser)
                    return promptResult
                },
                captureCount: { [unowned self] in captureCount },
                installAgent: { [unowned self] in installCalls += 1 },
                isAgentLoaded: { [unowned self] in agentLoaded }))
        model.onFinished = { [unowned self] in finished += 1 }
        return model
    }()
}
