import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI

@MainActor
@Suite("TabExtractor")
struct TabExtractorTests {
    @Test("Safari runs JavaScript through its own dialect")
    func safariScript() {
        #expect(
            TabExtractor.script(
                for: .safari, bundleID: "com.apple.Safari",
                javaScript: TabExtractor.documentHTMLJavaScript) == """
                    with timeout of 5 seconds
                        tell application id "com.apple.Safari"
                            do JavaScript "document.documentElement.outerHTML" \
                    in current tab of front window
                        end tell
                    end timeout
                    """)
    }

    @Test("Chromium browsers execute JavaScript in the active tab")
    func chromiumScript() {
        #expect(
            TabExtractor.script(
                for: .chromium, bundleID: "com.google.Chrome",
                javaScript: TabExtractor.documentHTMLJavaScript) == """
                    with timeout of 5 seconds
                        tell application id "com.google.Chrome"
                            execute active tab of front window \
                    javascript "document.documentElement.outerHTML"
                        end tell
                    end timeout
                    """)
    }

    @Test("JavaScript is escaped into the script")
    func scriptEscapesJavaScript() {
        let script = TabExtractor.script(
            for: .chromium, bundleID: "com.google.Chrome", javaScript: #"say("hi")"#)
        #expect(script.contains(#"javascript "say(\"hi\")""#))
    }

    @Test("Extraction asks the browser for its document HTML")
    func extractReturnsHTML() throws {
        let recorder = RecordingScriptRunner(.success("<html></html>"))

        let html = try TabExtractor(runner: recorder.runner).extractHTML(from: .dia)

        #expect(html == "<html></html>")
        #expect(
            recorder.sources == [
                TabExtractor.script(
                    for: .chromium, bundleID: "company.thebrowser.dia",
                    javaScript: TabExtractor.documentHTMLJavaScript)
            ])
    }

    @Test("A tab that returns nothing is an empty result", arguments: [nil, ""] as [String?])
    func extractEmptyResult(output: String?) {
        let recorder = RecordingScriptRunner(.success(output))
        #expect(throws: TabExtractionError.emptyResult) {
            try TabExtractor(runner: recorder.runner).extractHTML(from: .safari)
        }
    }

    @Test("A script error is passed through")
    func extractScriptError() {
        let recorder = RecordingScriptRunner(.failure(.automationDenied))
        #expect(throws: TabExtractionError.script(.automationDenied)) {
            try TabExtractor(runner: recorder.runner).extractHTML(from: .chrome)
        }
    }

    @Test(
        "Accessibility-only browsers are refused without running a script",
        arguments: [Browser.firefox, .zen, .librewolf, .waterfox, .search])
    func accessibilityOnlyBrowsersAreUnsupported(browser: Browser) {
        let recorder = RecordingScriptRunner(.success("<html></html>"))
        #expect(throws: TabExtractionError.unsupportedBrowser(browser)) {
            try TabExtractor(runner: recorder.runner).extractHTML(from: browser)
        }
        #expect(recorder.sources.isEmpty)
    }
}
