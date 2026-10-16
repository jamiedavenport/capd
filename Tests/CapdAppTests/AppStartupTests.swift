import AppKit
import CapdKit
import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdHandoff

@MainActor
@Suite("App startup")
struct AppStartupTests {
    @Test("Scene reads and delegate handoffs use the single startup state")
    func sharesStartupState() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("capd-app-startup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "capd-app-startup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.fetchesPageBodies = false
        let store = try Store(paths: StoragePaths(root: root))
        let service = CaptureService(store: store)
        var requests: [CaptureRequest] = []
        let coordinator = CaptureCoordinator(
            environment: CaptureEnvironment(
                isSecureInputActive: { false },
                frontmostTarget: { nil },
                selectedText: { _ in nil },
                browserTab: { _, _ in nil },
                pasteboardFallback: { .nothing },
                fetchBody: { false },
                ingest: {
                    requests.append($0)
                    return try service.ingest($0)
                },
                enrich: { _ in },
                now: Date.init),
            present: { _ in })
        let state = AppState(settings: settings, coordinator: coordinator)
        var startupSteps: [String] = []
        let app = CapdApp(
            installAgent: { startupSteps.append("agent") },
            makeState: {
                startupSteps.append("state")
                return state
            })

        #expect(startupSteps == ["agent", "state"])
        #expect(app.state === state)
        _ = app.body
        _ = app.body
        #expect(app.state === state)
        #expect(startupSteps == ["agent", "state"])

        let payload = ShareHandoff.Payload(
            url: "https://example.com/startup-handoff",
            title: "Startup handoff evidence",
            sourceAppBundleID: "com.apple.Safari")
        let url = try #require(ShareHandoff.url(for: payload))
        app.delegate.application(
            NSApplication.shared,
            open: [URL(string: "capd://capture")!, url])
        await coordinator.drain()

        #expect(requests.count == 1)
        #expect(requests.first?.url == payload.url)
        #expect(requests.first?.title == payload.title)
        #expect(requests.first?.sourceAppBundleID == payload.sourceAppBundleID)
        #expect(requests.first?.fetchBody == false)
        let model = SearchModel(
            environment: .live(
                searchService: SearchService(store: store), store: store, showHUD: { _ in }))
        model.queryText = "startup handoff evidence"
        await model.settle()
        #expect(model.hits.count == 1)
        #expect(model.hits.first?.capture.url == payload.url)
        #expect(model.totalCount == 1)
    }
}
