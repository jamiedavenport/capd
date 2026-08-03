import CapAppUI
import CapKit
import Foundation
import os

/// Everything the hotkey capture path reaches into, injectable so the decision logic
/// tests without AX, Apple Events, or a live pasteboard.
struct CaptureEnvironment {
    var isSecureInputActive: @MainActor () -> Bool
    var frontmostTarget: @MainActor () -> FrontmostTarget?
    var selectedText: @MainActor (FrontmostTarget) -> String?
    var browserTab: @MainActor (Browser, FrontmostTarget) async -> BrowserTab?
    var pasteboardFallback: @MainActor () async -> PasteboardFallbackResult
    var fetchBody: @MainActor () -> Bool
    var ingest: @MainActor (CaptureRequest) throws -> CaptureOutcome
    var enrich: @MainActor (Capture) async -> Void
    var now: () -> Date
}

/// Runs one capture per hotkey press, in press order.
///
/// Presses chain rather than coalesce: five rapid presses are five captures, and the
/// pasteboard restore of one never interleaves with the snapshot of the next.
@MainActor
final class CaptureCoordinator {
    private let environment: CaptureEnvironment
    private let present: (HUDContent) -> Void
    private let logger = Log.capture
    private var chain: Task<Void, Never>?
    private var enrichments: [UUID: Task<Void, Never>] = [:]

    init(environment: CaptureEnvironment, present: @escaping (HUDContent) -> Void) {
        self.environment = environment
        self.present = present
    }

    func capture() {
        chain = Task { [previous = chain] in
            await previous?.value
            await self.performCapture()
        }
    }

    /// Queues one capture per dropped item behind any captures already in flight.
    func capture(dropped items: [DroppedItem]) {
        chain = Task { [previous = chain] in
            await previous?.value
            self.performDropCapture(items)
        }
    }

    /// Queues a request built outside the app, e.g. from the share extension's handoff.
    func capture(request: CaptureRequest) {
        chain = Task { [previous = chain] in
            await previous?.value
            self.ingestAndPresent(request, fallbackNote: nil)
        }
    }

    /// Waits for every queued capture and every enrichment it started.
    func drain() async {
        await chain?.value
        for task in enrichments.values {
            await task.value
        }
    }

    private func performCapture() async {
        let clock = ContinuousClock()
        let start = clock.now

        // Checked before the AX read and the synthetic ⌘C, not just inside ingest's
        // guards: neither may run at all while typing is shielded.
        guard !environment.isSecureInputActive() else {
            present(.blocked())
            return
        }

        let target = environment.frontmostTarget()
        let browser = target?.bundleID.flatMap(Browser.init(bundleID:))
        var tab: BrowserTab?
        if let browser, let target {
            tab = await environment.browserTab(browser, target)
        }
        let selection = target.flatMap { environment.selectedText($0) }

        var text = selection
        var imageData: Data?
        var fallbackNote: String?
        if selection == nil {
            switch await environment.pasteboardFallback() {
            case .text(let copied):
                text = copied
            case .image(let data):
                imageData = data
            case .nothing:
                break
            case .skipped(let reason):
                fallbackNote = reason.explanation
            }
        }

        var url = tab?.url
        if url == nil, let candidate = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            LinkDetection.looksLikeURL(candidate)
        {
            url = candidate
            text = nil
        }

        let request = CaptureRequest(
            url: url,
            text: text,
            imageData: imageData,
            title: tab?.title,
            sourceAppBundleID: target?.bundleID,
            fetchBody: environment.fetchBody(),
            capturedAt: environment.now())

        ingestAndPresent(request, fallbackNote: fallbackNote)
        let elapsed = clock.now - start
        logger.info("hotkey to HUD in \(String(describing: elapsed), privacy: .public)")
    }

    private func performDropCapture(_ items: [DroppedItem]) {
        let requests = DropClassifier.requests(
            from: items,
            fetchBody: environment.fetchBody(),
            // During a drop the frontmost app is almost always the drag's source.
            sourceAppBundleID: environment.frontmostTarget()?.bundleID,
            now: environment.now())
        guard !requests.isEmpty else {
            present(.failure(CaptureError.emptyRequest, detail: nil))
            return
        }
        for request in requests {
            ingestAndPresent(request, fallbackNote: nil)
        }
    }

    private func ingestAndPresent(_ request: CaptureRequest, fallbackNote: String?) {
        let content: HUDContent
        var pendingLink: Capture?
        do {
            let outcome = try environment.ingest(request)
            content = .outcome(outcome, fallbackNote: fallbackNote, now: environment.now())
            let capture = outcome.capture
            if capture.kind == .link, capture.enrichmentState == .pending {
                pendingLink = capture
            }
        } catch {
            content = .failure(error, detail: fallbackNote)
        }

        present(content)

        if let pendingLink {
            let id = UUID()
            enrichments[id] = Task {
                await self.environment.enrich(pendingLink)
                self.enrichments[id] = nil
            }
        }
    }
}
