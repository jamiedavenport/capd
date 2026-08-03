import Foundation
import Synchronization
import Testing

@testable import CapApp
@testable import CapAppUI
@testable import CapKit

@MainActor
@Suite("Search model")
struct SearchModelTests {
    @Test("A slow early query cannot overwrite a fast later one")
    func slowQueryLosesToNewer() async {
        let gate = Gate()
        let slowHit = makeHit(id: 1, title: "Slow")
        let fastHit = makeHit(id: 2, title: "Fast")
        let model = SearchModel(
            environment: .stub(
                search: { text in
                    guard text == "slow" else { return [fastHit] }
                    await gate.wait()
                    return [slowHit]
                },
                totalCount: { 2 }))

        model.queryText = "slow"
        model.queryText = "fast"
        while model.hits.isEmpty { await Task.yield() }
        #expect(model.hits == [fastHit])

        gate.open()
        await model.settle()

        #expect(model.hits == [fastHit])
        #expect(model.totalCount == 2)
    }

    @Test("Each keystroke re-queries, and results reset the selection")
    func typingRefreshes() async {
        let first = makeHit(id: 1)
        let second = makeHit(id: 2)
        let model = SearchModel(
            environment: .stub(
                search: { text in text == "a" ? [first, second] : [second] },
                totalCount: { 7 }))

        model.queryText = "a"
        await model.settle()
        #expect(model.hits == [first, second])
        #expect(model.totalCount == 7)

        model.moveSelection(by: 1)
        model.queryText = "ab"
        await model.settle()

        #expect(model.hits == [second])
        #expect(model.selectedIndex == 0)
    }

    @Test("Activating clears the query and loads recents")
    func activateClearsQuery() async {
        let recent = makeHit(id: 9)
        let model = SearchModel(
            environment: .stub(search: { text in text.isEmpty ? [recent] : [] }))

        model.queryText = "stale"
        await model.settle()
        #expect(model.hits.isEmpty)

        model.activate()
        await model.settle()

        #expect(model.queryText.isEmpty)
        #expect(model.hits == [recent])
    }

    @Test("The selection clamps at both ends")
    func selectionClamps() async {
        let hits = [makeHit(id: 1), makeHit(id: 2), makeHit(id: 3)]
        let model = SearchModel(environment: .stub(search: { _ in hits }))
        model.queryText = "x"
        await model.settle()

        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 0)

        for _ in 0..<5 { model.moveSelection(by: 1) }
        #expect(model.selectedIndex == 2)
    }

    @Test("Opening a link opens its URL and dismisses")
    func openLink() async {
        let log = ActionLog()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [makeHit(id: 1, url: "https://example.com/a")] },
                openURL: { log.opened.append($0) }))
        model.onDismiss = { log.dismissed += 1 }
        model.queryText = "x"
        await model.settle()

        model.openSelected()

        #expect(log.opened == [URL(string: "https://example.com/a")!])
        #expect(log.dismissed == 1)
    }

    @Test("Opening a text capture copies its text instead")
    func openTextCopies() async {
        let log = ActionLog()
        let hit = makeHit(id: 1, kind: .text, url: nil, title: nil, selection: "let x = 1")
        let model = SearchModel(
            environment: .stub(search: { _ in [hit] }, copyText: { log.copied.append($0) }))
        model.onDismiss = { log.dismissed += 1 }
        model.queryText = "x"
        await model.settle()

        model.openSelected()

        #expect(log.copied == ["let x = 1"])
        #expect(log.dismissed == 1)
    }

    @Test("Opening an image capture opens its asset file")
    func openImageAsset() async {
        let log = ActionLog()
        let hit = makeHit(id: 1, kind: .image, url: nil, title: nil, assetPath: "ab/cd.png")
        let model = SearchModel(
            environment: .stub(
                search: { _ in [hit] },
                openURL: { log.opened.append($0) },
                assetFileURL: { URL(fileURLWithPath: "/assets/\($0)") }))
        model.queryText = "x"
        await model.settle()

        model.openSelected()

        #expect(log.opened == [URL(fileURLWithPath: "/assets/ab/cd.png")])
    }

    @Test("Copy prefers the URL and falls back to the text")
    func copyPrefersURL() async {
        let log = ActionLog()
        let link = makeHit(id: 1, url: "https://example.com/a", selection: "quoted")
        let text = makeHit(id: 2, kind: .text, url: nil, selection: "quoted")
        let model = SearchModel(
            environment: .stub(
                search: { _ in [link, text] }, copyText: { log.copied.append($0) }))
        model.queryText = "x"
        await model.settle()

        model.copySelected()
        model.moveSelection(by: 1)
        model.copySelected()

        #expect(log.copied == ["https://example.com/a", "quoted"])
    }

    @Test("Delete re-queries and keeps the selection in range")
    func deleteClampsSelection() async {
        let box = ResultsBox([makeHit(id: 1), makeHit(id: 2), makeHit(id: 3)])
        let log = ActionLog()
        let model = SearchModel(
            environment: .stub(
                search: { _ in box.hits },
                totalCount: { box.hits.count },
                delete: {
                    log.deleted.append($0)
                    box.remove(id: $0)
                }))
        model.queryText = "x"
        await model.settle()
        model.select(2)

        model.deleteSelected()
        await model.settle()

        #expect(log.deleted == [3])
        #expect(model.hits.map(\.capture.id) == [1, 2])
        #expect(model.selectedIndex == 1)
        #expect(model.totalCount == 2)
    }

    @Test("Actions with no results do nothing")
    func actionsWithoutResults() async {
        let log = ActionLog()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                openURL: { log.opened.append($0) },
                copyText: { log.copied.append($0) }))
        model.onDismiss = { log.dismissed += 1 }
        model.queryText = "x"
        await model.settle()

        model.openSelected()
        model.copySelected()
        model.deleteSelected()
        model.moveSelection(by: 1)

        #expect(log.opened.isEmpty)
        #expect(log.copied.isEmpty)
        #expect(log.dismissed == 0)
        #expect(model.selectedIndex == 0)
    }
}

@MainActor
private final class ActionLog {
    var opened: [URL] = []
    var copied: [String] = []
    var deleted: [Int64] = []
    var dismissed = 0
}

/// Result state shared between the `@Sendable` search closure and main-actor mutations.
private final class ResultsBox: Sendable {
    private let storage: Mutex<[SearchHit]>

    init(_ hits: [SearchHit]) {
        storage = Mutex(hits)
    }

    var hits: [SearchHit] {
        storage.withLock { $0 }
    }

    func remove(id: Int64) {
        storage.withLock { hits in hits.removeAll { $0.capture.id == id } }
    }
}

/// A one-shot latch: `wait()` suspends until `open()`, which may also come first.
private final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func open() {
        continuation.finish()
    }

    func wait() async {
        for await _ in stream {}
    }
}

private func makeHit(
    id: Int64,
    kind: CaptureKind = .link,
    url: String? = "https://example.com/x",
    title: String? = "A page",
    selection: String? = nil,
    assetPath: String? = nil
) -> SearchHit {
    SearchHit(
        capture: Capture(
            id: id,
            kind: kind,
            url: url,
            title: title,
            selection: selection,
            assetPath: assetPath,
            createdAt: Date(timeIntervalSince1970: 1_000_000)),
        snippet: nil,
        score: nil)
}

extension SearchEnvironment {
    @MainActor
    fileprivate static func stub(
        search: @escaping @Sendable (String) async throws -> [SearchHit],
        totalCount: @escaping @Sendable () async throws -> Int = { 0 },
        delete: @escaping @MainActor (Int64) throws -> Void = { _ in },
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        copyText: @escaping @MainActor (String) -> Void = { _ in },
        assetFileURL: @escaping @MainActor (String) -> URL? = { _ in nil }
    ) -> SearchEnvironment {
        SearchEnvironment(
            search: search,
            totalCount: totalCount,
            delete: delete,
            openURL: openURL,
            copyText: copyText,
            assetFileURL: assetFileURL)
    }
}
