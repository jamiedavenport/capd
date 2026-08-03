import CapdKit
import Foundation
import Observation

/// Everything the search window does to the rest of the system, injectable so tests can
/// drive queries and observe actions without a store, a pasteboard, or a browser.
@MainActor
package struct SearchEnvironment {
    var search: @Sendable (String) async throws -> [SearchHit]
    var totalCount: @Sendable () async throws -> Int
    var tags: @Sendable () async throws -> [String]
    var delete: @MainActor (Int64) throws -> Void
    var openURL: @MainActor (URL) -> Void
    var copyText: @MainActor (String) -> Void
    var assetFileURL: @MainActor (String) -> URL?
    var showHUD: @MainActor (HUDContent) -> Void

    package init(
        search: @escaping @Sendable (String) async throws -> [SearchHit],
        totalCount: @escaping @Sendable () async throws -> Int,
        tags: @escaping @Sendable () async throws -> [String] = { [] },
        delete: @escaping @MainActor (Int64) throws -> Void,
        openURL: @escaping @MainActor (URL) -> Void,
        copyText: @escaping @MainActor (String) -> Void,
        assetFileURL: @escaping @MainActor (String) -> URL?,
        showHUD: @escaping @MainActor (HUDContent) -> Void
    ) {
        self.search = search
        self.totalCount = totalCount
        self.tags = tags
        self.delete = delete
        self.openURL = openURL
        self.copyText = copyText
        self.assetFileURL = assetFileURL
        self.showHUD = showHUD
    }
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
            // Typing takes over from the cycled filter: two competing tag filters would
            // be impossible to reason about from the search field.
            activeTag = nil
            refresh()
        }
    }

    /// Every tag in use, most used first — the ⇥ cycle order.
    private(set) var availableTags: [String] = []
    /// The tag the ⇥ cycle is filtering by; nil is the "all captures" stop.
    private(set) var activeTag: String?

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
    @ObservationIgnored private var tagLoad: Task<Void, Never>?

    init(environment: SearchEnvironment) {
        self.environment = environment
    }

    var selectedHit: SearchHit? {
        hits.indices.contains(selectedIndex) ? hits[selectedIndex] : nil
    }

    /// Called each time the window is summoned: fresh query, fresh recents, fresh tag
    /// cycle, focused field.
    func activate() {
        focusToken &+= 1
        let alreadyClear = queryText.isEmpty && activeTag == nil
        activeTag = nil
        queryText = ""
        if alreadyClear { refresh() }

        let fetch = environment.tags
        tagLoad = Task { [weak self] in
            let tags = (try? await fetch()) ?? []
            self?.availableTags = tags
        }
    }

    /// ⇥ and ⇧⇥ walk the tag filters with "all captures" as the stop between the ends.
    func cycleTag(forward: Bool) {
        guard !availableTags.isEmpty else { return }
        if let current = activeTag, let index = availableTags.firstIndex(of: current) {
            if forward {
                let next = index + 1
                activeTag = next < availableTags.count ? availableTags[next] : nil
            } else {
                activeTag = index > 0 ? availableTags[index - 1] : nil
            }
        } else {
            activeTag = forward ? availableTags.first : availableTags.last
        }
        refresh()
    }

    /// A click on a tag chip jumps straight to that filter; clicking the active one clears it.
    func toggleTag(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
        refresh()
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
            environment.showHUD(.copied(capture))
        }
        dismiss()
    }

    func copySelected() {
        guard let capture = selectedHit?.capture else { return }
        guard let text = capture.url ?? Self.primaryText(of: capture) else { return }
        environment.copyText(text)
        environment.showHUD(.copied(capture))
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
        if let task = tagLoad {
            await task.value
            tagLoad = nil
        }
        while let (key, task) = inflight.first {
            await task.value
            inflight[key] = nil
        }
    }

    private func refresh(preservingSelection: Bool = false) {
        generation &+= 1
        let expected = generation
        // Appended after the typed text so a cycled tag always wins: the parser keeps
        // the last tag: token it sees.
        let text = activeTag.map { "\(queryText) tag:\($0)" } ?? queryText
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
