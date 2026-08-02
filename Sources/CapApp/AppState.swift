import AppKit
import CapKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// Owns every live object behind the menu bar: the store, the capture path, and the HUD.
@MainActor
@Observable
final class AppState {
    private(set) var failedEnrichmentCount = 0
    private(set) var startupFailure: String?

    @ObservationIgnored private var coordinator: CaptureCoordinator?
    @ObservationIgnored private var hud: HUDPanelController?
    @ObservationIgnored private var badgeTask: Task<Void, Never>?

    init() {
        do {
            try start()
        } catch {
            startupFailure = error.localizedDescription
        }
    }

    private func start() throws {
        let store = try Store(paths: .live)
        let captureService = CaptureService(
            store: store,
            guards: [SecureInputGuard(probes: [SystemSecureInputProbe(), AXReader()])])
        let enricher = BodyEnricher(enrichment: EnrichmentService(store: store))

        let hud = HUDPanelController(saveNote: { id, note in
            _ = try? captureService.annotate(id, note: note)
        })
        self.hud = hud

        coordinator = CaptureCoordinator(
            environment: .live(
                ingest: { try captureService.ingest($0) },
                enrich: { await enricher.enrich($0) }),
            present: { hud.show($0) })

        KeyboardShortcuts.onKeyDown(for: .capture) { [weak self] in
            self?.coordinator?.capture()
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
}

extension CaptureEnvironment {
    static func live(
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
            ingest: ingest,
            enrich: enrich,
            now: Date.init)
    }
}
