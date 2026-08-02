import CapKit
import Foundation
import Testing

@testable import CapApp

/// The onboarding flow's guided loop, end to end on a fresh install: the first hotkey
/// capture must be findable by the first search, through the app's real write and read
/// paths.
@MainActor
@Suite("Cold start")
struct ColdStartTests {
    @Test("Fresh install: the first search finds the first capture")
    func firstSearchFindsFirstCapture() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cap-cold-start-\(UUID().uuidString)", isDirectory: true)
        let store = try Store(paths: StoragePaths(root: root))
        let service = CaptureService(store: store)

        let coordinator = CaptureCoordinator(
            environment: CaptureEnvironment(
                isSecureInputActive: { false },
                frontmostTarget: {
                    FrontmostTarget(
                        bundleID: "com.apple.Safari", name: "Safari", processIdentifier: 1)
                },
                selectedText: { _ in nil },
                browserTab: { _ in
                    BrowserTab(
                        url: "https://example.com/swift-testing",
                        title: "Swift Testing guide")
                },
                pasteboardFallback: { .nothing },
                fetchBody: { false },
                ingest: { try service.ingest($0) },
                enrich: { _ in },
                now: Date.init),
            present: { _ in })

        coordinator.capture()
        await coordinator.drain()

        let model = SearchModel(
            environment: .live(searchService: SearchService(store: store), store: store))
        model.queryText = "swift testing"
        await model.settle()

        #expect(model.hits.count == 1)
        #expect(model.hits.first?.capture.url == "https://example.com/swift-testing")
        #expect(model.totalCount == 1)
    }
}
