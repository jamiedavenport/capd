import Foundation
import Synchronization
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdKit

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

    @Test("Copying shows a copied toast in the HUD")
    func copyShowsToast() async {
        let log = ActionLog()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [makeHit(id: 1, url: "https://example.com/a")] },
                showHUD: { log.toasts.append($0) }))
        model.queryText = "x"
        await model.settle()

        model.copySelected()

        #expect(log.toasts.map(\.style) == [.copied])
        #expect(log.toasts.map(\.headline) == ["Copied to clipboard"])
        #expect(log.toasts.map(\.detail) == ["A page"])
    }

    @Test("Opening a text capture shows the copied toast too")
    func openTextShowsToast() async {
        let log = ActionLog()
        let hit = makeHit(id: 1, kind: .text, url: nil, title: nil, selection: "let x = 1")
        let model = SearchModel(
            environment: .stub(search: { _ in [hit] }, showHUD: { log.toasts.append($0) }))
        model.queryText = "x"
        await model.settle()

        model.openSelected()

        #expect(log.toasts.map(\.style) == [.copied])
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

    @Test("Tab cycles every tag with all-captures as the stop between the ends")
    func tabCycle() async {
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                tags: { ["swift", "databases"] }))
        model.activate()
        await model.settle()
        #expect(model.availableTags == ["swift", "databases"])

        model.cycleTag(forward: true)
        #expect(model.activeTag == "swift")
        model.cycleTag(forward: true)
        #expect(model.activeTag == "databases")
        model.cycleTag(forward: true)
        #expect(model.activeTag == nil)

        model.cycleTag(forward: false)
        #expect(model.activeTag == "databases")
        model.cycleTag(forward: false)
        #expect(model.activeTag == "swift")
        model.cycleTag(forward: false)
        #expect(model.activeTag == nil)
    }

    @Test("Clicking a tag filters by it; clicking it again clears the filter")
    func toggleTag() async {
        let seen = Mutex<[String]>([])
        let model = SearchModel(
            environment: .stub(
                search: { text in
                    seen.withLock { $0.append(text) }
                    return []
                },
                tags: { ["swift", "databases"] }))
        model.activate()
        await model.settle()

        model.toggleTag("databases")
        await model.settle()
        #expect(model.activeTag == "databases")
        #expect(seen.withLock { $0.last } == " tag:databases")

        model.toggleTag("swift")
        #expect(model.activeTag == "swift")

        model.toggleTag("swift")
        await model.settle()
        #expect(model.activeTag == nil)
        #expect(seen.withLock { $0.last } == "")
    }

    @Test("A cycled tag rides the query as a trailing tag: token")
    func cycledTagFilters() async {
        let seen = Mutex<[String]>([])
        let model = SearchModel(
            environment: .stub(
                search: { text in
                    seen.withLock { $0.append(text) }
                    return []
                },
                tags: { ["swift"] }))
        model.activate()
        await model.settle()

        model.queryText = "notes"
        await model.settle()
        model.cycleTag(forward: true)
        await model.settle()

        #expect(seen.withLock { $0.last } == "notes tag:swift")
    }

    @Test("Typing hands the filter back to the query text")
    func typingResetsCycledTag() async {
        let model = SearchModel(
            environment: .stub(search: { _ in [] }, tags: { ["swift"] }))
        model.activate()
        await model.settle()

        model.cycleTag(forward: true)
        #expect(model.activeTag == "swift")

        model.queryText = "n"
        #expect(model.activeTag == nil)
    }

    @Test("Summoning the window clears the cycled tag and reloads the cycle")
    func activateResetsCycle() async {
        let available = Mutex(["old"])
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                tags: { available.withLock { $0 } }))
        model.activate()
        await model.settle()
        model.cycleTag(forward: true)
        #expect(model.activeTag == "old")

        available.withLock { $0 = ["fresh"] }
        model.activate()
        await model.settle()

        #expect(model.activeTag == nil)
        #expect(model.availableTags == ["fresh"])
    }

    @Test("Cycling with no tags is inert")
    func cycleWithoutTags() async {
        let model = SearchModel(environment: .stub(search: { _ in [] }))
        model.activate()
        await model.settle()

        model.cycleTag(forward: true)
        #expect(model.activeTag == nil)
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

    @Test("Ask Cap publishes a cited answer without dismissing search")
    func askCapAnswers() async {
        let answer = makeAnswer()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                answerAvailability: { .available },
                answer: { question in
                    #expect(question == "swift cancellation")
                    return answer
                }))
        model.queryText = "swift cancellation"

        model.askCap()
        #expect(model.isAnswering)
        await model.settle()

        #expect(model.libraryAnswer == answer)
        #expect(model.answerError == nil)
        #expect(model.isAnswerMode)
    }

    @Test("Ask Cap stays at item zero and captures follow it")
    func askCapIsFirstItem() async {
        let hits = [makeHit(id: 1), makeHit(id: 2)]
        let asked = Mutex<[String]>([])
        let model = SearchModel(
            environment: .stub(
                search: { _ in hits },
                answerAvailability: { .available },
                answer: { question in
                    asked.withLock { $0.append(question) }
                    return makeAnswer()
                }))

        model.activate()
        await model.settle()

        #expect(model.showsAskOption)
        #expect(model.selectedIndex == 0)
        #expect(model.isAskSelected)
        #expect(model.selectedHit == nil)

        model.submit()
        await model.settle()
        #expect(asked.withLock { $0 }.isEmpty)

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 1)
        #expect(model.selectedHit == hits[0])
        #expect(model.isCaptureSelected(0))

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 2)
        #expect(model.selectedHit == hits[1])
        #expect(model.isCaptureSelected(1))

        model.moveSelection(by: -2)
        #expect(model.selectedIndex == 0)
        #expect(model.isAskSelected)

        model.queryText = "What did I save?"
        await model.settle()
        #expect(model.selectedIndex == 0)
        model.submit()
        await model.settle()
        #expect(asked.withLock { $0 } == ["What did I save?"])
    }

    @Test("A question-mark query makes Return ask instead of opening a result")
    func questionMarkSubmit() async {
        let log = ActionLog()
        let seen = Mutex<[String]>([])
        let model = SearchModel(
            environment: .stub(
                search: { _ in [makeHit(id: 1)] },
                answerAvailability: { .available },
                answer: { question in
                    seen.withLock { $0.append(question) }
                    return makeAnswer()
                },
                openURL: { log.opened.append($0) }))
        model.queryText = "? What did I save about Swift?"
        await model.settle()

        model.submit()
        await model.settle()

        #expect(seen.withLock { $0 } == ["What did I save about Swift?"])
        #expect(log.opened.isEmpty)
        #expect(model.libraryAnswer != nil)
    }

    @Test("Editing the query keeps a stale answer from publishing")
    func editingCancelsAnswer() async {
        let gate = Gate()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                answerAvailability: { .available },
                answer: { _ in
                    await gate.wait()
                    return makeAnswer()
                }))
        model.queryText = "first question"
        model.askCap()
        #expect(model.isAnswering)

        model.queryText = "second question"
        gate.open()
        await model.settle()

        #expect(!model.isAnswerMode)
        #expect(model.libraryAnswer == nil)
    }

    @Test("Citations open their capture and dismiss")
    func openCitation() async {
        let log = ActionLog()
        let model = SearchModel(
            environment: .stub(
                search: { _ in [] },
                answerAvailability: { .available },
                answer: { _ in makeAnswer() },
                openCapture: { log.openedCaptures.append($0) }))
        model.onDismiss = { log.dismissed += 1 }
        model.queryText = "swift"
        model.askCap()
        await model.settle()

        model.openAnswerSource(1)

        #expect(log.openedCaptures == [42])
        #expect(log.dismissed == 1)
    }
}

@MainActor
private final class ActionLog {
    var opened: [URL] = []
    var openedCaptures: [Int64] = []
    var copied: [String] = []
    var deleted: [Int64] = []
    var toasts: [HUDContent] = []
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
        tags: @escaping @Sendable () async throws -> [String] = { [] },
        answerAvailability: @escaping @Sendable () -> LibraryAnswerAvailability = {
            .unavailable(.unknown)
        },
        answer: @escaping @Sendable (String) async throws -> LibraryAnswer = { _ in
            throw LibraryAnswerError.unavailable(.unknown)
        },
        delete: @escaping @MainActor (Int64) throws -> Void = { _ in },
        openCapture: @escaping @MainActor (Int64) -> Void = { _ in },
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        copyText: @escaping @MainActor (String) -> Void = { _ in },
        assetFileURL: @escaping @MainActor (String) -> URL? = { _ in nil },
        showHUD: @escaping @MainActor (HUDContent) -> Void = { _ in }
    ) -> SearchEnvironment {
        SearchEnvironment(
            search: search,
            totalCount: totalCount,
            tags: tags,
            answerAvailability: answerAvailability,
            answer: answer,
            delete: delete,
            openCapture: openCapture,
            openURL: openURL,
            copyText: copyText,
            assetFileURL: assetFileURL,
            showHUD: showHUD)
    }
}

private func makeAnswer() -> LibraryAnswer {
    LibraryAnswer(
        question: "swift cancellation",
        passages: [
            .init(text: "Cancellation is cooperative.", citations: [1])
        ],
        sources: [
            .init(
                number: 1,
                captureID: 42,
                kind: .link,
                title: "Swift cancellation",
                url: "https://example.com/swift",
                host: "example.com",
                excerpt: "Cancellation is cooperative.")
        ])
}
