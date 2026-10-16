import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI

@Suite("BrowserTabReader")
struct BrowserTabReaderTests {
    @Test("Safari reads the current tab through its own dialect")
    func safariScript() throws {
        let script = try #require(BrowserTabReader.script(for: .safari))

        #expect(
            script == """
                with timeout of 2 seconds
                    tell application id "com.apple.Safari"
                        set theTab to current tab of front window
                        (URL of theTab) & linefeed & (name of theTab)
                    end tell
                end timeout
                """)
    }

    @Test(
        "Chromium browsers share a dialect and differ only in bundle id",
        arguments: [Browser.chrome, Browser.arc])
    func chromiumScript(browser: Browser) throws {
        let script = try #require(BrowserTabReader.script(for: browser))

        #expect(
            script == """
                with timeout of 2 seconds
                    tell application id "\(browser.rawValue)"
                        set theTab to active tab of front window
                        (URL of theTab) & linefeed & (title of theTab)
                    end tell
                end timeout
                """)
    }

    @Test(
        "Accessibility-only browsers have no Apple Events tab script",
        arguments: [Browser.firefox, .zen, .librewolf, .waterfox, .search])
    func accessibilityBrowsersHaveNoScript(browser: Browser) {
        #expect(BrowserTabReader.script(for: browser) == nil)
    }

    @Test("The first line is the URL and the rest is the title")
    func parseSplitsURLAndTitle() {
        let tab = BrowserTabReader.parse("https://example.com/a\nAn example page")
        #expect(tab == BrowserTab(url: "https://example.com/a", title: "An example page"))
    }

    @Test("A linefeed in the title cannot corrupt the URL")
    func parseKeepsMultilineTitleWhole() {
        let tab = BrowserTabReader.parse("https://example.com/a\nline one\nline two")
        #expect(tab == BrowserTab(url: "https://example.com/a", title: "line one\nline two"))
    }

    @Test("A missing title comes back nil")
    func parseWithoutTitle() {
        #expect(
            BrowserTabReader.parse("https://example.com/a\n")
                == BrowserTab(url: "https://example.com/a", title: nil))
        #expect(
            BrowserTabReader.parse("https://example.com/a")
                == BrowserTab(url: "https://example.com/a", title: nil))
    }

    @Test("Accessibility title fallback keeps a nonempty page title first")
    func resolvedTitlePrefersPageTitle() {
        #expect(
            AXBrowserTabReader.resolvedTitle(
                "  Page title  ", accessibilityDescription: "Capture - Capd")
                == "Page title")
    }

    @Test("Accessibility title fallback trims whitespace and uses the description")
    func resolvedTitleUsesDescriptionWhenPageTitleIsBlank() {
        #expect(
            AXBrowserTabReader.resolvedTitle(
                "  \n", accessibilityDescription: "  Capture - Capd  "
            )
                == "Capture - Capd")
    }

    @Test("Accessibility title fallback uses a nonempty description when title is missing")
    func resolvedTitleUsesDescriptionWhenTitleIsMissing() {
        #expect(
            AXBrowserTabReader.resolvedTitle(
                nil, accessibilityDescription: "Capture - Capd")
                == "Capture - Capd")
    }

    @Test("Accessibility title fallback is nil when both values are missing or blank")
    func resolvedTitleIsNilWithoutEitherValue() {
        #expect(
            AXBrowserTabReader.resolvedTitle(
                nil, accessibilityDescription: nil) == nil)
        #expect(
            AXBrowserTabReader.resolvedTitle(
                "  ", accessibilityDescription: "\n") == nil)
    }

    @Test("Empty output is not a tab")
    func parseEmptyOutput() {
        #expect(BrowserTabReader.parse("") == nil)
        #expect(BrowserTabReader.parse("\nA title with no URL") == nil)
    }
}
