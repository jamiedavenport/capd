import AppKit
import ApplicationServices
import CapKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// Owns every live object behind the menu bar: the store, the capture path, and the HUD.
@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    let updates: UpdateChecker

    private(set) var failedEnrichmentCount = 0
    private(set) var startupFailure: String?

    @ObservationIgnored private var coordinator: CaptureCoordinator?
    @ObservationIgnored private var hud: HUDPanelController?
    @ObservationIgnored private var search: SearchWindowController?
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private var totalCaptures: (() -> Int)?
    @ObservationIgnored private var badgeTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    init() {
        let settings = AppSettings()
        self.settings = settings
        updates = UpdateChecker(settings: settings, client: .gitHubReleases)

        do {
            try start()
        } catch {
            startupFailure = error.localizedDescription
        }

        if !settings.hasCompletedOnboarding {
            presentOnboarding()
        }

        // Runs even when the store fails to open: the update signal is the one path
        // that must reach an install broken enough to need it.
        updateTask = Task { [updates] in
            while !Task.isCancelled {
                await updates.checkIfDue()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func showSearch() {
        onboarding?.noteSearchOpened()
        search?.show()
    }

    private func start() throws {
        let store = try Store(paths: .live)
        let captureService = CaptureService(
            store: store,
            guards: [SecureInputGuard(probes: [SystemSecureInputProbe(), AXReader()])])
        let enrichment = EnrichmentService(store: store, steps: [TabFirstBodyStep()])

        let hud = HUDPanelController(saveNote: { id, note in
            _ = try? captureService.annotate(id, note: note)
        })
        self.hud = hud

        let settings = self.settings
        coordinator = CaptureCoordinator(
            environment: .live(
                fetchBody: { settings.fetchesPageBodies },
                ingest: { try captureService.ingest($0) },
                enrich: { capture in
                    guard let id = capture.id else { return }
                    _ = try? await enrichment.process(captureID: id)
                }),
            present: { hud.show($0) })

        let searchService = SearchService(store: store)
        search = SearchWindowController(
            environment: .live(searchService: searchService, store: store))
        totalCaptures = { (try? searchService.totalCaptureCount()) ?? 0 }

        KeyboardShortcuts.onKeyDown(for: .capture) { [weak self] in
            self?.coordinator?.capture()
        }

        KeyboardShortcuts.onKeyDown(for: .search) { [weak self] in
            self?.onboarding?.noteSearchOpened()
            self?.search?.toggle()
        }

        badgeTask = Task { [weak self] in
            do {
                for try await count in store.failedEnrichmentCounts() {
                    guard let self else { return }
                    self.failedEnrichmentCount = count
                }
            } catch {}
        }
    }

    private func presentOnboarding() {
        let controller = OnboardingWindowController(
            environment: .live(captureCount: { [weak self] in self?.totalCaptures?() ?? 0 }))
        controller.onFinished = { [weak self] in
            self?.settings.hasCompletedOnboarding = true
        }
        controller.onClosed = { [weak self] in
            self?.onboarding = nil
        }
        onboarding = controller
        controller.show()
    }
}

extension OnboardingEnvironment {
    static func live(captureCount: @escaping @MainActor () -> Int) -> OnboardingEnvironment {
        OnboardingEnvironment(
            shortcut: { KeyboardShortcuts.getShortcut(for: $0) },
            isShortcutTakenBySystem: { $0.isTakenBySystem },
            isAXTrusted: { AXIsProcessTrusted() },
            requestAXTrust: {
                // kAXTrustedCheckOptionPrompt spelled out: Swift 6 rejects the C global
                // as shared mutable state.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            },
            openAXSettings: {
                openSystemSettings(pane: "Privacy_Accessibility")
            },
            openAutomationSettings: {
                openSystemSettings(pane: "Privacy_Automation")
            },
            runningBrowsers: {
                Browser.allCases.filter { browser in
                    !NSRunningApplication
                        .runningApplications(withBundleIdentifier: browser.rawValue).isEmpty
                }
            },
            automationStatus: { AutomationConsent.status(for: $0, askIfNeeded: false) },
            requestAutomationConsent: { browser in
                // The consent dialog blocks the calling thread until answered.
                await Task.detached {
                    AutomationConsent.status(for: browser, askIfNeeded: true)
                }.value
            },
            captureCount: captureCount,
            installAgent: { AgentBootstrap.installAgent() },
            isAgentLoaded: { AgentBootstrap.isAgentLoaded() })
    }

    private static func openSystemSettings(pane: String) {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

extension SearchEnvironment {
    static func live(searchService: SearchService, store: Store) -> SearchEnvironment {
        SearchEnvironment(
            search: { try searchService.search($0) },
            totalCount: { try searchService.totalCaptureCount() },
            delete: { _ = try store.deleteCaptures(ids: [$0]) },
            openURL: { NSWorkspace.shared.open($0) },
            copyText: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            assetFileURL: { store.paths.assetURL(forRelativePath: $0) })
    }
}

extension CaptureEnvironment {
    static func live(
        fetchBody: @escaping @MainActor () -> Bool,
        ingest: @escaping @MainActor (CaptureRequest) throws -> CaptureOutcome,
        enrich: @escaping @MainActor (Capture) async -> Void
    ) -> CaptureEnvironment {
        CaptureEnvironment(
            isSecureInputActive: {
                SystemSecureInputProbe().isSecureInputActive() || AXReader().isSecureInputActive()
            },
            frontmostTarget: { FrontmostTarget.current() },
            selectedText: {
                SelectionReader().selectedText(inAppWithProcessIdentifier: $0.processIdentifier)
            },
            browserTab: { BrowserTabReader.read($0) },
            pasteboardFallback: { await PasteboardFallback().copySelection() },
            fetchBody: fetchBody,
            ingest: ingest,
            enrich: enrich,
            now: Date.init)
    }
}
