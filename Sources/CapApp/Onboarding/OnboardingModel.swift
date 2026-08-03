import AppKit
import KeyboardShortcuts
import Observation

enum OnboardingStep: Int, CaseIterable {
    case hotkeys
    case accessibility
    case browsers
    case firstCapture
}

/// Everything the first-run flow reads or pokes, injectable so the flow tests without
/// TCC dialogs, Apple Events, launchd, or a live store.
struct OnboardingEnvironment {
    var shortcut: @MainActor (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    var isShortcutTakenBySystem: @MainActor (KeyboardShortcuts.Shortcut) -> Bool
    var isAXTrusted: @MainActor () -> Bool
    var requestAXTrust: @MainActor () -> Void
    var openAXSettings: @MainActor () -> Void
    var openAutomationSettings: @MainActor () -> Void
    var runningBrowsers: @MainActor () -> [Browser]
    var automationStatus: @MainActor (Browser) -> AutomationConsentStatus
    var requestAutomationConsent: @MainActor (Browser) async -> AutomationConsentStatus
    var captureCount: @MainActor () -> Int
    var installAgent: @MainActor () -> Void
    var isAgentLoaded: @MainActor () -> Bool
}

/// Drives the first-run window: walks the steps, mirrors permission state, and latches
/// the guided first capture and first search.
@MainActor
@Observable
final class OnboardingModel {
    private let environment: OnboardingEnvironment
    var onFinished: (() -> Void)?

    private(set) var step: OnboardingStep = .hotkeys
    private(set) var captureShortcut: String?
    private(set) var searchShortcut: String?
    private(set) var conflicted: Set<KeyboardShortcuts.Name> = []
    private(set) var axTrusted = false
    private(set) var runningBrowsers: [Browser] = []
    private(set) var consents: [Browser: AutomationConsentStatus] = [:]
    private(set) var pendingConsents: [Browser: Task<Void, Never>] = [:]
    private(set) var hasCaptured = false
    private(set) var hasSearched = false
    private(set) var agentLoaded = false

    init(environment: OnboardingEnvironment) {
        self.environment = environment
        environment.installAgent()
        refresh()
    }

    var isLastStep: Bool {
        step == OnboardingStep.allCases.last
    }

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    func requestAccessibility() {
        environment.requestAXTrust()
    }

    func openAccessibilitySettings() {
        environment.openAXSettings()
    }

    func openAutomationSettings() {
        environment.openAutomationSettings()
    }

    @discardableResult
    func requestConsent(for browser: Browser) -> Task<Void, Never> {
        let task = Task {
            consents[browser] = await environment.requestAutomationConsent(browser)
            pendingConsents[browser] = nil
        }
        pendingConsents[browser] = task
        return task
    }

    func noteSearchOpened() {
        hasSearched = true
    }

    func finish() {
        onFinished?()
    }

    /// Re-reads every externally owned fact; the window polls this while visible so
    /// grants and the guided capture flip to done without a restart.
    func refresh() {
        captureShortcut = environment.shortcut(.capture)?.description
        searchShortcut = environment.shortcut(.search)?.description
        conflicted = Set(
            [KeyboardShortcuts.Name.capture, .annotate, .search].filter { name in
                guard let shortcut = environment.shortcut(name) else { return false }
                return environment.isShortcutTakenBySystem(shortcut)
            })
        axTrusted = environment.isAXTrusted()
        agentLoaded = environment.isAgentLoaded()
        if !hasCaptured, environment.captureCount() > 0 {
            hasCaptured = true
        }
        runningBrowsers = environment.runningBrowsers().filter(\.supportsTabExtraction)
        for browser in runningBrowsers where pendingConsents[browser] == nil {
            consents[browser] = environment.automationStatus(browser)
        }
    }
}
