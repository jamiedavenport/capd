import CapKit
import Foundation
import GRDB
import Testing

@testable import CapApp
@testable import CapAppUI

@MainActor
@Suite("CaptureCoordinator")
struct CaptureCoordinatorTests {
    @Test("A browser press captures the tab's link with the AX selection attached")
    func browserCapturesLinkWithSelection() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/a", title: "An example page")
        harness.selection = "A quoted phrase"

        harness.coordinator.capture()
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/a")
        #expect(request.text == "A quoted phrase")
        #expect(request.title == "An example page")
        #expect(request.sourceAppBundleID == "com.apple.Safari")
        #expect(harness.fallbackCalls == 0)
        #expect(harness.presented.first?.style == .captured)
        #expect(harness.presented.first?.headline == "Captured")
    }

    @Test("An unrestorable clipboard skips the fallback and captures the link alone")
    func skippedFallbackCapturesLinkOnly() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/a", title: nil)
        harness.fallbackResult = .skipped(.promisedContent)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/a")
        #expect(request.text == nil)
        #expect(harness.fallbackCalls == 1)
        let content = try #require(harness.presented.first)
        #expect(content.headline == "Captured link only")
        #expect(content.detail?.contains("promised files") == true)
    }

    @Test("Outside a browser, the copied selection becomes a text capture")
    func fallbackTextBecomesTextCapture() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "com.apple.dt.Xcode", name: "Xcode", processIdentifier: 7)
        harness.fallbackResult = .text("let x = 1")

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.requests.first?.url == nil)
        #expect(harness.requests.first?.text == "let x = 1")
        #expect(harness.presented.first?.style == .captured)
        #expect(harness.enriched.isEmpty)
    }

    @Test("A copied URL alone becomes a link capture")
    func fallbackURLBecomesLinkCapture() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "app.zen-browser.zen", name: "Zen", processIdentifier: 7)
        harness.fallbackResult = .text("  https://example.com/copied\n")

        harness.coordinator.capture()
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/copied")
        #expect(request.text == nil)
        #expect(harness.enriched.count == 1)
    }

    @Test("A selected URL becomes a link capture when no tab is readable")
    func selectedURLBecomesLinkCapture() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "com.apple.dt.Xcode", name: "Xcode", processIdentifier: 7)
        harness.selection = "https://example.com/selected"

        harness.coordinator.capture()
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/selected")
        #expect(request.text == nil)
    }

    @Test("Prose that mentions a link stays a text capture")
    func proseWithLinkStaysText() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "com.apple.dt.Xcode", name: "Xcode", processIdentifier: 7)
        harness.fallbackResult = .text("check https://example.com too")

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.requests.first?.url == nil)
        #expect(harness.requests.first?.text == "check https://example.com too")
    }

    @Test("The tab's URL beats a URL-shaped selection")
    func tabURLBeatsSelectedURL() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/tab", title: nil)
        harness.selection = "https://example.com/selected"

        harness.coordinator.capture()
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/tab")
        #expect(request.text == "https://example.com/selected")
    }

    @Test("A copied image becomes an image capture and is left for the agent")
    func fallbackImageBecomesImageCapture() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "com.apple.Preview", name: "Preview", processIdentifier: 7)
        harness.fallbackResult = .image(samplePNG)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.requests.first?.imageData == samplePNG)
        #expect(harness.presented.first?.style == .captured)
        #expect(harness.enriched.isEmpty)
    }

    @Test("Secure input blocks before anything is read")
    func secureInputBlocksBeforeReading() async throws {
        let harness = try Harness()
        harness.secureInput = true
        harness.tab = BrowserTab(url: "https://example.com/a", title: nil)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.requests.isEmpty)
        #expect(harness.fallbackCalls == 0)
        #expect(harness.presented.first?.style == .blocked)
    }

    @Test("A press with nothing to capture says so")
    func emptyPressFails() async throws {
        let harness = try Harness()
        harness.target = FrontmostTarget(
            bundleID: "com.apple.finder", name: "Finder", processIdentifier: 7)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.presented.first?.style == .failed)
        #expect(harness.presented.first?.headline == "Nothing to capture.")
    }

    @Test("Five rapid presses are five captures, in order")
    func burstPressesAllCapture() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/a", title: "An example page")
        harness.selection = "A quoted phrase"

        for _ in 1...5 {
            harness.coordinator.capture()
        }
        await harness.coordinator.drain()

        #expect(harness.requests.count == 5)
        #expect(harness.presented.count == 5)
        #expect(harness.presented.first?.style == .captured)
        #expect(harness.presented.dropFirst().allSatisfy { $0.style == .duplicate })
        let seenCount = try await harness.store.reader.read { db in
            try Capture.fetchOne(db)?.seenCount
        }
        #expect(seenCount == 5)
    }

    @Test("Re-capturing says when it was last seen")
    func duplicateSaysWhenLastSeen() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/a", title: nil)

        harness.coordinator.capture()
        harness.coordinator.capture()
        await harness.coordinator.drain()

        let second = try #require(harness.presented.last)
        #expect(second.style == .duplicate)
        #expect(second.headline.hasPrefix("Already captured"))
    }

    @Test("A pending link capture starts enrichment")
    func pendingLinkStartsEnrichment() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/a", title: nil)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.enriched.count == 1)
        #expect(harness.enriched.first?.url == "https://example.com/a")
    }

    @Test("A dropped link captures like a hotkey press and queues enrichment")
    func droppedLinkCaptures() async throws {
        let harness = try Harness()

        harness.coordinator.capture(dropped: [
            DroppedItem(urlString: "https://example.com/a", urlTitle: "An example page")
        ])
        await harness.coordinator.drain()

        let request = try #require(harness.requests.first)
        #expect(request.url == "https://example.com/a")
        #expect(request.title == "An example page")
        #expect(request.sourceAppBundleID == "com.apple.Safari")
        #expect(harness.presented.first?.style == .captured)
        #expect(harness.enriched.count == 1)
    }

    @Test("Every dropped item becomes its own capture, in order")
    func multiItemDropCapturesEach() async throws {
        let harness = try Harness()

        harness.coordinator.capture(dropped: [
            DroppedItem(string: "first note"),
            DroppedItem(string: "second note"),
        ])
        await harness.coordinator.drain()

        #expect(harness.requests.map(\.text) == ["first note", "second note"])
        #expect(harness.presented.count == 2)
        #expect(harness.presented.allSatisfy { $0.style == .captured })
    }

    @Test("A drop with nothing capturable says so")
    func emptyDropFails() async throws {
        let harness = try Harness()

        harness.coordinator.capture(dropped: [DroppedItem(string: "   ")])
        await harness.coordinator.drain()

        #expect(harness.requests.isEmpty)
        #expect(harness.presented.first?.style == .failed)
        #expect(harness.presented.first?.headline == "Nothing to capture.")
    }

    @Test("A drop queues behind a hotkey press already in flight")
    func dropQueuesBehindHotkey() async throws {
        let harness = try Harness()
        harness.tab = BrowserTab(url: "https://example.com/tab", title: nil)

        harness.coordinator.capture()
        harness.coordinator.capture(dropped: [
            DroppedItem(urlString: "https://example.com/dropped")
        ])
        await harness.coordinator.drain()

        #expect(
            harness.requests.map(\.url) == [
                "https://example.com/tab", "https://example.com/dropped",
            ])
    }

    @Test("The fetch opt-out stores the link without queuing enrichment")
    func fetchOptOutSkipsEnrichment() async throws {
        let harness = try Harness()
        harness.fetchBody = false
        harness.tab = BrowserTab(url: "https://example.com/a", title: nil)

        harness.coordinator.capture()
        await harness.coordinator.drain()

        #expect(harness.requests.first?.fetchBody == false)
        #expect(harness.enriched.isEmpty)
        #expect(harness.presented.first?.style == .captured)
    }
}

/// A coordinator wired to stub inputs and a real store in a throwaway directory.
@MainActor
private final class Harness {
    let store: Store
    private(set) var coordinator: CaptureCoordinator!

    var requests: [CaptureRequest] = []
    var presented: [HUDContent] = []
    var enriched: [Capture] = []
    var fallbackCalls = 0
    var fallbackResult: PasteboardFallbackResult = .nothing
    var fetchBody = true
    var secureInput = false
    var target: FrontmostTarget? = FrontmostTarget(
        bundleID: "com.apple.Safari", name: "Safari", processIdentifier: 1)
    var selection: String?
    var tab: BrowserTab?

    init() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cap-coordinator-tests-\(UUID().uuidString)", isDirectory: true)
        store = try Store(paths: StoragePaths(root: root))
        let service = CaptureService(store: store)

        coordinator = CaptureCoordinator(
            environment: CaptureEnvironment(
                isSecureInputActive: { [unowned self] in secureInput },
                frontmostTarget: { [unowned self] in target },
                selectedText: { [unowned self] _ in selection },
                browserTab: { [unowned self] _, _ in tab },
                pasteboardFallback: { [unowned self] in
                    fallbackCalls += 1
                    return fallbackResult
                },
                fetchBody: { [unowned self] in fetchBody },
                ingest: { [unowned self] request in
                    requests.append(request)
                    return try service.ingest(request)
                },
                enrich: { [unowned self] capture in enriched.append(capture) },
                now: Date.init),
            present: { [unowned self] content in presented.append(content) })
    }
}

private let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
