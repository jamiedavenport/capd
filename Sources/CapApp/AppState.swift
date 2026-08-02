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
    @ObservationIgnored private var search: SearchWindowController?
    @ObservationIgnored private var badgeTask: Task<Void, Never>?

    init() {
        do {
            try start()
        } catch {
            startupFailure = error.localizedDescription
        }
    }

    func showSearch() {
        search?.show()
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

        search = SearchWindowController(
            environment: .live(searchService: SearchService(store: store), store: store))

        KeyboardShortcuts.onKeyDown(for: .capture) { [weak self] in
            self?.coordinator?.capture()
        }

        KeyboardShortcuts.onKeyDown(for: .search) { [weak self] in
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
