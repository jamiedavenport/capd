import CapKit
import Foundation
import Observation

/// Everything the search window does to the rest of the system, injectable so tests can
/// drive queries and observe actions without a store, a pasteboard, or a browser.
@MainActor
struct SearchEnvironment {
    var search: @Sendable (String) async throws -> [SearchHit]
    var totalCount: @Sendable () async throws -> Int
    var delete: @MainActor (Int64) throws -> Void
    var openURL: @MainActor (URL) -> Void
    var copyText: @MainActor (String) -> Void
    var assetFileURL: @MainActor (String) -> URL?
}

/// Drives the search window: a query per keystroke, off the main thread, and only the
/// newest generation may publish, so a slow early query can never overwrite a fast
/// later one.
@MainActor
@Observable
final class SearchModel {
    var queryText = "" {
        didSet {
            guard queryText != oldValue else { return }
            refresh()
        }
    }

    private(set) var hits: [SearchHit] = []
    private(set) var totalCount = 0
    private(set) var selectedIndex = 0
    /// False until the first query answers, so an open window shows nothing rather than
    /// flashing the wrong empty state.
    private(set) var hasLoaded = false
    /// Bumped each time the window is summoned; the view refocuses the field on change.
    private(set) var focusToken = 0

    @ObservationIgnored var onDismiss: (() -> Void)?

    @ObservationIgnored private let environment: SearchEnvironment
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inflight: [Int: Task<Void, Never>] = [:]

    init(environment: SearchEnvironment) {
        self.environment = environment
    }

    var selectedHit: SearchHit? {
        hits.indices.contains(selectedIndex) ? hits[selectedIndex] : nil
    }

    /// Called each time the window is summoned: fresh query, fresh recents, focused field.
    func activate() {
        focusToken &+= 1
        let alreadyEmpty = queryText.isEmpty
        queryText = ""
        if alreadyEmpty { refresh() }
    }

    func moveSelection(by delta: Int) {
        guard !hits.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), hits.count - 1)
    }

    func select(_ index: Int) {
        guard hits.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Links open in the browser, images in their viewer; a bare text capture has nowhere
    /// to go, so its text lands on the pasteboard instead.
    func openSelected() {
        guard let capture = selectedHit?.capture else { return }
        if let url = capture.url.flatMap(URL.init(string:)) {
            environment.openURL(url)
        } else if let path = capture.assetPath, let file = environment.assetFileURL(path) {
            environment.openURL(file)
        } else if let text = Self.primaryText(of: capture) {
            environment.copyText(text)
        }
        dismiss()
    }

    func copySelected() {
        guard let capture = selectedHit?.capture else { return }
        guard let text = capture.url ?? Self.primaryText(of: capture) else { return }
        environment.copyText(text)
        dismiss()
    }

    func deleteSelected() {
        guard let id = selectedHit?.capture.id else { return }
        do {
            try environment.delete(id)
        } catch {
            return
        }
        refresh(preservingSelection: true)
    }

    func dismiss() {
        onDismiss?()
    }

    /// Waits for every issued query, including ones that lost the generation race. Test hook.
    func settle() async {
        while let (key, task) = inflight.first {
            await task.value
            inflight[key] = nil
        }
    }

    private func refresh(preservingSelection: Bool = false) {
        generation &+= 1
        let expected = generation
        let text = queryText
        let search = environment.search
        let count = environment.totalCount
        inflight[expected] = Task { [weak self] in
            let hits = (try? await search(text)) ?? []
            let total = (try? await count()) ?? 0
            guard let self else { return }
            self.inflight[expected] = nil
            guard self.generation == expected else { return }
            self.apply(hits: hits, total: total, preservingSelection: preservingSelection)
        }
    }

    private func apply(hits: [SearchHit], total: Int, preservingSelection: Bool) {
        self.hits = hits
        totalCount = total
        hasLoaded = true
        selectedIndex = preservingSelection ? max(0, min(selectedIndex, hits.count - 1)) : 0
    }

    static func primaryText(of capture: Capture) -> String? {
        capture.selection ?? capture.body ?? capture.ocrText ?? capture.note ?? capture.title
    }
}
