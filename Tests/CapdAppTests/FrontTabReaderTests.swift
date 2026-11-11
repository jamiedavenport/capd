import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI

@MainActor
@Suite("FrontTabReader")
struct FrontTabReaderTests {
    @MainActor
    final class Harness {
        let scripts = RecordingScriptRunner(.success("https://example.com/script\nScripted"))
        var accessibilityReads: [(pid: pid_t, options: AccessibilityTabOptions)] = []

        var reader: FrontTabReader {
            FrontTabReader(
                runner: scripts.runner,
                accessibility: { [self] pid, options in
                    accessibilityReads.append((pid, options))
                    return BrowserTab(url: "https://example.com/ax", title: "Accessible")
                })
        }

        func read(_ browser: Browser, route: FrontTabReader.Route = .native) async -> BrowserTab? {
            await reader.read(
                browser,
                target: FrontmostTarget(
                    bundleID: browser.rawValue, name: browser.displayName, processIdentifier: 42),
                route: route)
        }
    }

    @Test(
        "Scriptable browsers are read over Apple Events",
        arguments: [Browser.safari, .chrome, .arc, .helium, .dia])
    func scriptableBrowsersUseAppleEvents(browser: Browser) async {
        let harness = Harness()

        let tab = await harness.read(browser)

        #expect(tab == BrowserTab(url: "https://example.com/script", title: "Scripted"))
        #expect(harness.scripts.sources.count == 1)
        #expect(harness.scripts.sources.first?.contains(browser.rawValue) == true)
        #expect(harness.accessibilityReads.isEmpty)
    }

    @Test(
        "Other browsers are read over Accessibility with their own options",
        arguments: [Browser.firefox, .zen, .librewolf, .waterfox, .search])
    func accessibilityBrowsersUseAccessibility(browser: Browser) async {
        let harness = Harness()

        let tab = await harness.read(browser)

        #expect(tab == BrowserTab(url: "https://example.com/ax", title: "Accessible"))
        #expect(harness.scripts.sources.isEmpty)
        #expect(harness.accessibilityReads.map(\.pid) == [42])
        #expect(browser.tabAccess == .accessibility(harness.accessibilityReads[0].options))
    }

    @Test("The accessibility-only route never sends Apple Events", arguments: Browser.allCases)
    func accessibilityOnlyRoute(browser: Browser) async {
        let harness = Harness()

        let tab = await harness.read(browser, route: .accessibilityOnly)

        #expect(tab == BrowserTab(url: "https://example.com/ax", title: "Accessible"))
        #expect(harness.scripts.sources.isEmpty)
        #expect(harness.accessibilityReads.count == 1)
    }

    @Test("Scriptable browsers on the accessibility-only route are not primed")
    func accessibilityOnlyLeavesChromiumUnprimed() async {
        let harness = Harness()

        _ = await harness.read(.dia, route: .accessibilityOnly)

        #expect(harness.accessibilityReads.map(\.options) == [AccessibilityTabOptions()])
    }
}
