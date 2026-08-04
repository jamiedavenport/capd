import AppKit
import ApplicationServices
import CapdAppUI
import CapdHandoff
import CapdKit
import KeyboardShortcuts
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Owns every live object behind the menu bar: the store, the capture path, and the HUD.
@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    let updates: UpdateChecker
    let permissions: PermissionMonitor

    private(set) var failedEnrichmentCount = 0
    private(set) var startupFailure: String?
    private(set) var isDropTargeted = false

    @ObservationIgnored private var coordinator: CaptureCoordinator?
    @ObservationIgnored private var hud: HUDPanelController?
    @ObservationIgnored private var search: SearchWindowController?
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private var statusItemDrop: StatusItemDropTarget?
    @ObservationIgnored private var contextMonitor: AmbientContextMonitor?
    @ObservationIgnored private let contextSuppressions = ContextSuppressionRegistry()
    @ObservationIgnored private let dragMonitor = DragMonitor()
    @ObservationIgnored private var totalCaptures: (() -> Int)?
    @ObservationIgnored private var pinboardImporter: PinboardImporter?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var badgeTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?

    enum MenuBarGlyph {
        case dropTarget
        case degraded
        case normal
    }

    var menuBarGlyph: MenuBarGlyph {
        if isDropTargeted {
            return .dropTarget
        }
        if failedEnrichmentCount > 0 || startupFailure != nil || permissions.axLost {
            return .degraded
        }
        return .normal
    }

    init() {
        let settings = AppSettings()
        self.settings = settings
        updates = UpdateChecker(settings: settings, client: .gitHubReleases)
        permissions = PermissionMonitor(environment: .live(settings: settings))

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

        permissions.onLoss = { [weak self] in
            self?.presentAXLossPrompt()
        }
        // The first check runs off init so the loss alert never blocks launch.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.permissions.check()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func showSearch() {
        onboarding?.noteSearchOpened()
        search?.show()
    }

    func showOnboarding() {
        if let onboarding {
            onboarding.show()
        } else {
            presentOnboarding()
        }
    }

    /// Asks for a Pinboard JSON export and replays it through the capture path off the
    /// main actor, so a multi-thousand-bookmark file never freezes the menu bar.
    func importFromPinboard() {
        guard let importer = pinboardImporter, importTask == nil else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose the JSON backup from pinboard.in (Settings → Backup)"
        panel.prompt = "Import"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importTask = Task { [weak self] in
            let result = await Task.detached {
                Result { try importer.run(data: try Data(contentsOf: url)) }
            }.value
            self?.importTask = nil
            self?.presentImportResult(result)
        }
    }

    /// Captures pages handed over as `capd://capture` URLs, e.g. by the share extension.
    func capture(handoffs urls: [URL]) {
        for url in urls {
            guard let payload = ShareHandoff.payload(from: url) else {
                Log.capture.error("dropped a malformed handoff URL")
                continue
            }
            coordinator?.capture(
                request: CaptureRequest(
                    url: payload.url,
                    title: payload.title,
                    sourceAppBundleID: payload.sourceAppBundleID,
                    fetchBody: settings.fetchesPageBodies))
        }
    }

    private func start() throws {
        let store = try Store(paths: .live)
        let captureService = CaptureService(
            store: store,
            guards: [SecureInputGuard(probes: [SystemSecureInputProbe(), AXReader()])])
        let enrichment = EnrichmentService(store: store, steps: [TabFirstBodyStep()])
        let favicons = FaviconStore(paths: store.paths)
        // Ungated: the secure-input guard protects reading the screen, and an import
        // reads a file the user just picked.
        pinboardImporter = PinboardImporter(captures: CaptureService(store: store))

        let hud = HUDPanelController(
            favicons: favicons,
            saveNote: { id, note in
                _ = try? captureService.annotate(id, note: note)
            })
        self.hud = hud

        let settings = self.settings
        coordinator = CaptureCoordinator(
            environment: .live(
                fetchBody: { settings.fetchesPageBodies },
                ingest: { [contextSuppressions] request in
                    let outcome = try captureService.ingest(request)
                    contextSuppressions.register(capture: outcome.capture)
                    return outcome
                },
                enrich: { capture in
                    guard let id = capture.id else { return }
                    _ = try? await enrichment.process(captureID: id)
                }),
            present: { hud.show($0) })

        hud.performDrop = { [weak self] items in
            self?.coordinator?.capture(dropped: items)
        }
        statusItemDrop = StatusItemDropTarget(
            onTargeted: { [weak self] targeted in self?.isDropTargeted = targeted },
            onDrop: { [weak self] items in self?.coordinator?.capture(dropped: items) })
        statusItemDrop?.install()

        dragMonitor.onDragMoved = { [weak hud] mouse in hud?.dragMoved(to: mouse) }
        dragMonitor.onDragEnded = { [weak hud] in hud?.dragEnded() }
        dragMonitor.start()

        // Seeded before the write-through closure is wired, so reflecting the stored
        // flag cannot immediately write it back.
        settings.autoTagsCaptures = (try? store.taxonomy().taggingEnabled) ?? true
        settings.saveAutoTags = { try? store.setTaggingEnabled($0) }
        settings.requestRetagging = { try? store.requestRetagging() }
        if case .unavailable(let reason) = FoundationModelTagger().availability() {
            settings.autoTagsUnavailableReason = reason.explanation
        }

        let searchService = SearchService(store: store)
        let insightEngine = ContextInsightEngine(providers: [
            PreviouslySavedInsightProvider(findCapture: { try searchService.capture(url: $0) })
        ])
        let contextMonitor = AmbientContextMonitor(
            environment: AmbientContextEnvironment(
                isSecureInputActive: {
                    SystemSecureInputProbe().isSecureInputActive()
                        || AXReader().isSecureInputActive()
                },
                frontmostTarget: { FrontmostTarget.current() },
                browserTab: { _, target in
                    await AXBrowserTabReader.read(processIdentifier: target.processIdentifier)
                },
                isSuppressed: { [contextSuppressions] in contextSuppressions.contains($0) },
                insight: { await insightEngine.insight(for: $0) },
                present: { insight in
                    guard insight.kind == .previouslySaved else { return }
                    hud.show(.previouslySaved(insight.capture, now: Date()))
                },
                now: Date.init))
        self.contextMonitor = contextMonitor
        settings.contextualRemindersChanged = { [weak contextMonitor] enabled in
            if enabled {
                contextMonitor?.start()
            } else {
                contextMonitor?.stop()
            }
        }
        if settings.contextualRemindersEnabled {
            contextMonitor.start()
        }

        search = SearchWindowController(
            environment: .live(
                searchService: searchService,
                store: store,
                openURL: { [settings, contextSuppressions] url in
                    contextSuppressions.register(url)
                    NSWorkspace.shared.open(
                        CapdLinkAttribution.attributed(
                            url, enabled: settings.contextualRemindersEnabled))
                },
                showHUD: { hud.show($0) }),
            favicons: favicons)
        totalCaptures = { (try? searchService.totalCaptureCount()) ?? 0 }

        KeyboardShortcuts.onKeyDown(for: .capture) { [weak self] in
            self?.coordinator?.capture()
        }

        KeyboardShortcuts.onKeyDown(for: .annotate) { [weak self] in
            self?.hud?.beginAnnotation()
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

    private func presentImportResult(_ result: Result<PinboardImportSummary, any Error>) {
        let alert = NSAlert()
        switch result {
        case .success(let summary):
            alert.messageText = "Pinboard import complete"
            var lines = [
                "Imported \(summary.imported) new bookmarks and merged "
                    + "\(summary.merged) already in your library."
            ]
            if !summary.failures.isEmpty {
                lines.append("\(summary.failures.count) could not be imported.")
            }
            alert.informativeText = lines.joined(separator: " ")
        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = "Pinboard import failed"
            alert.informativeText = error.localizedDescription
        }
        NSApp.activate()
        alert.runModal()
    }

    private func presentAXLossPrompt() {
        let alert = NSAlert()
        alert.messageText = "Capd lost Accessibility access"
        alert.informativeText =
            "macOS drops the grant when the app's code signature changes, such as after "
            + "an update. Until it's re-granted, capture can't read selected text and "
            + "falls back to the clipboard, and contextual reminders are suspended."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openAccessibilitySettings()
        }
    }

    private func presentOnboarding() {
        let controller = OnboardingWindowController(
            environment: .live(
                settings: settings,
                captureCount: { [weak self] in self?.totalCaptures?() ?? 0 }))
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

extension PermissionMonitorEnvironment {
    static func live(settings: AppSettings) -> PermissionMonitorEnvironment {
        PermissionMonitorEnvironment(
            isAXTrusted: { AXIsProcessTrusted() },
            wasGrantedBefore: { settings.axGrantedBefore },
            setWasGrantedBefore: { settings.axGrantedBefore = $0 },
            openAXSettings: { openSystemSettings(pane: "Privacy_Accessibility") })
    }
}

extension OnboardingEnvironment {
    static func live(
        settings: AppSettings,
        captureCount: @escaping @MainActor () -> Int
    ) -> OnboardingEnvironment {
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
            openIntelligenceSettings: {
                guard
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")
                else { return }
                NSWorkspace.shared.open(url)
            },
            taggerAvailability: { FoundationModelTagger().availability() },
            shareExtensionStatus: { ShareExtensionElection.status() },
            enableShareExtension: { ShareExtensionElection.enable() },
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
            contextualRemindersEnabled: { settings.contextualRemindersEnabled },
            setContextualRemindersEnabled: { settings.contextualRemindersEnabled = $0 },
            installAgent: { AgentBootstrap.installAgent() },
            isAgentLoaded: { AgentBootstrap.isAgentLoaded() })
    }
}

private func openSystemSettings(pane: String) {
    guard
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    else { return }
    NSWorkspace.shared.open(url)
}

extension SearchEnvironment {
    static func live(
        searchService: SearchService,
        store: Store,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        showHUD: @escaping @MainActor (HUDContent) -> Void
    ) -> SearchEnvironment {
        let answers = LibraryAnswerService(search: searchService)
        return SearchEnvironment(
            search: { try searchService.search($0) },
            totalCount: { try searchService.totalCaptureCount() },
            tags: { try store.tagUsage().map(\.tag) },
            answerAvailability: { answers.availability() },
            answer: { try await answers.answer($0) },
            delete: { _ = try store.deleteCaptures(ids: [$0]) },
            openCapture: { id in
                guard let capture = try? searchService.capture(id: id) else { return }
                if let rawURL = capture.url, let url = URL(string: rawURL) {
                    openURL(url)
                } else if let path = capture.assetPath {
                    NSWorkspace.shared.open(store.paths.assetURL(forRelativePath: path))
                } else if let text =
                    capture.selection ?? capture.body ?? capture.ocrText ?? capture.note
                    ?? capture.title
                {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    showHUD(.copied(capture))
                }
            },
            openIntelligenceSettings: {
                guard
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")
                else { return }
                NSWorkspace.shared.open(url)
            },
            openURL: openURL,
            copyText: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            assetFileURL: { store.paths.assetURL(forRelativePath: $0) },
            showHUD: showHUD)
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
            browserTab: { browser, target in
                browser.isGecko
                    ? await GeckoTabReader.read(processIdentifier: target.processIdentifier)
                    : BrowserTabReader.read(browser)
            },
            pasteboardFallback: { await PasteboardFallback().copySelection() },
            fetchBody: fetchBody,
            ingest: ingest,
            enrich: enrich,
            now: Date.init)
    }
}
