import Foundation
import Testing

@testable import CapApp

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

    @Test("Firefox has no tab script")
    func firefoxHasNoScript() {
        #expect(BrowserTabReader.script(for: .firefox) == nil)
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

    @Test("Empty output is not a tab")
    func parseEmptyOutput() {
        #expect(BrowserTabReader.parse("") == nil)
        #expect(BrowserTabReader.parse("\nA title with no URL") == nil)
    }
}
