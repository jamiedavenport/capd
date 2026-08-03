import AppKit
import CapdKit
import KeyboardShortcuts
import Observation

enum OnboardingStep: Int, CaseIterable {
    case overview
    case hotkeys
    case permissions
    case firstCapture
}

/// Everything the first-run flow reads or pokes, injectable so the flow tests without
/// TCC dialogs, Apple Events, launchd, or a live store.
package struct OnboardingEnvironment {
    var shortcut: @MainActor (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    var isShortcutTakenBySystem: @MainActor (KeyboardShortcuts.Shortcut) -> Bool
    var isAXTrusted: @MainActor () -> Bool
    var requestAXTrust: @MainActor () -> Void
    var openAXSettings: @MainActor () -> Void
    var openAutomationSettings: @MainActor () -> Void
    var openIntelligenceSettings: @MainActor () -> Void
    var taggerAvailability: @MainActor () -> TaggerAvailability
    var shareExtensionStatus: @MainActor () -> ShareExtensionStatus
    var enableShareExtension: @MainActor () -> Void
    var runningBrowsers: @MainActor () -> [Browser]
    var automationStatus: @MainActor (Browser) -> AutomationConsentStatus
    var requestAutomationConsent: @MainActor (Browser) async -> AutomationConsentStatus
    var captureCount: @MainActor () -> Int
    var installAgent: @MainActor () -> Void
    var isAgentLoaded: @MainActor () -> Bool

    package init(
        shortcut: @escaping @MainActor (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?,
        isShortcutTakenBySystem: @escaping @MainActor (KeyboardShortcuts.Shortcut) -> Bool,
        isAXTrusted: @escaping @MainActor () -> Bool,
        requestAXTrust: @escaping @MainActor () -> Void,
        openAXSettings: @escaping @MainActor () -> Void,
        openAutomationSettings: @escaping @MainActor () -> Void,
        openIntelligenceSettings: @escaping @MainActor () -> Void,
        taggerAvailability: @escaping @MainActor () -> TaggerAvailability,
        shareExtensionStatus: @escaping @MainActor () -> ShareExtensionStatus,
        enableShareExtension: @escaping @MainActor () -> Void,
        runningBrowsers: @escaping @MainActor () -> [Browser],
        automationStatus: @escaping @MainActor (Browser) -> AutomationConsentStatus,
        requestAutomationConsent: @escaping @MainActor (Browser) async -> AutomationConsentStatus,
        captureCount: @escaping @MainActor () -> Int,
        installAgent: @escaping @MainActor () -> Void,
        isAgentLoaded: @escaping @MainActor () -> Bool
    ) {
        self.shortcut = shortcut
        self.isShortcutTakenBySystem = isShortcutTakenBySystem
        self.isAXTrusted = isAXTrusted
        self.requestAXTrust = requestAXTrust
        self.openAXSettings = openAXSettings
        self.openAutomationSettings = openAutomationSettings
        self.openIntelligenceSettings = openIntelligenceSettings
        self.taggerAvailability = taggerAvailability
        self.shareExtensionStatus = shareExtensionStatus
        self.enableShareExtension = enableShareExtension
        self.runningBrowsers = runningBrowsers
        self.automationStatus = automationStatus
        self.requestAutomationConsent = requestAutomationConsent
        self.captureCount = captureCount
        self.installAgent = installAgent
        self.isAgentLoaded = isAgentLoaded
    }
}

/// Drives the first-run window: walks the steps, mirrors permission state, and latches
/// the guided first capture and first search.
@MainActor
@Observable
final class OnboardingModel {
    private let environment: OnboardingEnvironment
    var onFinished: (() -> Void)?
    var onDeferred: (() -> Void)?

    private(set) var step: OnboardingStep = .overview
    private(set) var captureShortcut: String?
    private(set) var searchShortcut: String?
    private(set) var conflicted: Set<KeyboardShortcuts.Name> = []
    private(set) var axTrusted = false
    private(set) var taggerAvailability: TaggerAvailability = .available
    private(set) var shareStatus: ShareExtensionStatus = .unregistered
    private(set) var runningBrowsers: [Browser] = []
    private var primedShareExtension = false
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

    func openIntelligenceSettings() {
        environment.openIntelligenceSettings()
    }

    func enableShareExtension() {
        environment.enableShareExtension()
        shareStatus = environment.shareExtensionStatus()
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

    func deferSetup() {
        onDeferred?()
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
        taggerAvailability = environment.taggerAvailability()
        shareStatus = environment.shareExtensionStatus()
        // A never-touched election flips to enabled unprompted, like the agent
        // install; an explicit off in System Settings stays the user's call.
        if shareStatus == .defaulted, !primedShareExtension {
            primedShareExtension = true
            enableShareExtension()
        }
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
