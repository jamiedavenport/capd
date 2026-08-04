import Foundation
import GRDB
import Synchronization
import Testing

@testable import CapdKit

@Suite("Library answers")
struct LibraryAnswerServiceTests {
    @Test("A natural-language question retrieves topic words and returns cited claims")
    func answersFromRetrievedCaptures() async throws {
        try await withAnswerStore { store in
            let targetID = try insert(
                Capture(
                    kind: .link,
                    url: "https://example.com/swift-cancellation",
                    host: "example.com",
                    title: "Swift concurrency cancellation",
                    body: "Cancellation is cooperative. Tasks check for cancellation explicitly.",
                    createdAt: Date(timeIntervalSince1970: 2)),
                into: store)
            _ = try insert(
                Capture(
                    kind: .link,
                    url: "https://example.com/other",
                    host: "example.com",
                    title: "Concurrency elsewhere",
                    body: "A general overview of concurrent systems.",
                    createdAt: Date(timeIntervalSince1970: 1)),
                into: store)

            let observed = Mutex<[LibraryAnswerPromptSource]>([])
            let model = StubAnswerModel { _, sources in
                observed.withLock { $0 = sources }
                return LibraryAnswerDraft(
                    statements: [
                        .init(
                            text: "Swift task cancellation is cooperative.",
                            sourceNumbers: [1])
                    ])
            }
            let service = LibraryAnswerService(
                search: SearchService(store: store), model: model)

            let answer = try await service.answer(
                "What did I save about Swift concurrency cancellation?")

            #expect(
                answer.passages == [
                    .init(text: "Swift task cancellation is cooperative.", citations: [1])
                ])
            #expect(answer.sources.first?.captureID == targetID)
            #expect(answer.sources.first?.number == 1)
            #expect(observed.withLock { $0.first?.excerpt.contains("cooperative") } == true)
        }
    }

    @Test("Invalid citations and unsupported statements never reach the answer")
    func sanitizesClaims() async throws {
        try await withAnswerStore { store in
            _ = try insert(
                Capture(
                    kind: .text,
                    title: "Subscription notes",
                    selection: "Subscriptions can make long-term costs hard to predict.",
                    createdAt: Date()),
                into: store)
            let model = StubAnswerModel { _, _ in
                LibraryAnswerDraft(
                    statements: [
                        .init(text: " Costs are less predictable. ", sourceNumbers: [1, 99, 1]),
                        .init(text: "Costs are less predictable.", sourceNumbers: [1]),
                        .init(text: "An unsupported addition.", sourceNumbers: [99]),
                    ])
            }
            let service = LibraryAnswerService(
                search: SearchService(store: store), model: model)

            let answer = try await service.answer("arguments against subscriptions")

            #expect(
                answer.passages == [
                    .init(text: "Costs are less predictable.", citations: [1])
                ])
        }
    }

    @Test("A question mark prefix is syntax, not part of retrieval")
    func questionPrefix() {
        #expect(
            LibraryAnswerService.normalizedQuestion(" ?  local-first software ")
                == "local-first software")
        #expect(
            LibraryAnswerService.significantTerms(
                in: "What was that article about local-first software?")
                == ["article", "local-first", "software"])
    }

    @Test("Availability is checked before retrieval or generation")
    func unavailableModel() async throws {
        try await withAnswerStore { store in
            let model = StubAnswerModel(availability: .unavailable(.appleIntelligenceOff)) {
                _, _ in
                Issue.record("The unavailable model should not be called")
                return LibraryAnswerDraft(statements: [])
            }
            let service = LibraryAnswerService(
                search: SearchService(store: store), model: model)

            await #expect(throws: LibraryAnswerError.unavailable(.appleIntelligenceOff)) {
                try await service.answer("swift")
            }
        }
    }

    @Test("No matching captures produces a useful failure")
    func noMatches() async throws {
        try await withAnswerStore { store in
            let service = LibraryAnswerService(
                search: SearchService(store: store),
                model: StubAnswerModel { _, _ in
                    LibraryAnswerDraft(statements: [])
                })

            await #expect(throws: LibraryAnswerError.noMatches) {
                try await service.answer("a topic that is absent")
            }
        }
    }
}

private struct StubAnswerModel: LibraryAnswerModel {
    let state: LibraryAnswerAvailability
    let response:
        @Sendable (String, [LibraryAnswerPromptSource]) async throws
            -> LibraryAnswerDraft

    init(
        availability: LibraryAnswerAvailability = .available,
        response:
            @escaping @Sendable (String, [LibraryAnswerPromptSource]) async throws
            -> LibraryAnswerDraft
    ) {
        state = availability
        self.response = response
    }

    func availability() -> LibraryAnswerAvailability { state }

    func answer(
        question: String,
        sources: [LibraryAnswerPromptSource]
    ) async throws -> LibraryAnswerDraft {
        try await response(question, sources)
    }
}

private func withAnswerStore(_ body: (Store) async throws -> Void) async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-answer-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(try Store(paths: StoragePaths(root: root)))
}

@discardableResult
private func insert(_ capture: Capture, into store: Store) throws -> Int64 {
    try store.dbPool.write { db in
        var capture = capture
        try capture.insert(db)
        return try #require(capture.id)
    }
}
