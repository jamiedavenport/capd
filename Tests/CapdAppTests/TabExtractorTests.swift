import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI

@Suite("TabExtractor")
struct TabExtractorTests {
    @Test("Safari runs JavaScript through its own dialect")
    func safariScript() throws {
        let script = try #require(
            TabExtractor.script(for: .safari, javaScript: TabExtractor.documentHTMLJavaScript))

        #expect(
            script == """
                with timeout of 5 seconds
                    tell application id "com.apple.Safari"
                        do JavaScript "document.documentElement.outerHTML" \
                in current tab of front window
                    end tell
                end timeout
                """)
    }

    @Test(
        "Chromium browsers share a dialect and differ only in bundle id",
        arguments: [Browser.chrome, Browser.arc])
    func chromiumScript(browser: Browser) throws {
        let script = try #require(
            TabExtractor.script(for: browser, javaScript: TabExtractor.documentHTMLJavaScript))

        #expect(
            script == """
                with timeout of 5 seconds
                    tell application id "\(browser.rawValue)"
                        execute active tab of front window \
                javascript "document.documentElement.outerHTML"
                    end tell
                end timeout
                """)
    }

    @Test(
        "Gecko browsers have no tab extraction and route to the network fetch",
        arguments: [Browser.firefox, .zen, .librewolf, .waterfox])
    func geckoHasNoScript(browser: Browser) {
        #expect(browser.isGecko)
        #expect(browser.supportsTabExtraction == false)
        #expect(TabExtractor.script(for: browser, javaScript: "1 + 1") == nil)
    }

    @Test(
        "Bundle ids map to browsers exactly",
        arguments: [
            ("com.apple.Safari", Browser.safari),
            ("com.google.Chrome", Browser.chrome),
            ("company.thebrowser.Browser", Browser.arc),
            ("org.mozilla.firefox", Browser.firefox),
            ("app.zen-browser.zen", Browser.zen),
            ("org.mozilla.librewolf", Browser.librewolf),
            ("net.waterfox.waterfox", Browser.waterfox),
        ])
    func bundleIDsMapExactly(bundleID: String, expected: Browser) {
        #expect(Browser(bundleID: bundleID) == expected)
    }

    @Test(
        "Unknown apps are not browsers",
        arguments: ["com.apple.SAFARI", "com.microsoft.edgemac", "com.apple.dt.Xcode", ""])
    func unknownBundleIDsAreRefused(bundleID: String) {
        #expect(Browser(bundleID: bundleID) == nil)
    }

    @Test("JavaScript survives the trip into an AppleScript string literal")
    func stringLiteralEscaping() {
        #expect(
            TabExtractor.appleScriptStringLiteral(#"a "quoted" \path"#)
                == #"a \"quoted\" \\path"#)
        #expect(
            TabExtractor.appleScriptStringLiteral("line one\nline\ttwo\r")
                == #"line one\nline\ttwo\r"#)
        #expect(
            TabExtractor.appleScriptStringLiteral(TabExtractor.documentHTMLJavaScript)
                == TabExtractor.documentHTMLJavaScript)
    }
}
