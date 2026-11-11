import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI

@MainActor
@Suite("AppleEventsTabReader")
struct AppleEventsTabReaderTests {
    @Test("Safari reads the current tab through its own dialect")
    func safariScript() {
        #expect(
            AppleEventsTabReader.script(for: .safari, bundleID: "com.apple.Safari") == """
                with timeout of 2 seconds
                    tell application id "com.apple.Safari"
                        set theTab to current tab of front window
                        (URL of theTab) & linefeed & (name of theTab)
                    end tell
                end timeout
                """)
    }

    @Test("Chromium browsers read the active tab")
    func chromiumScript() {
        #expect(
            AppleEventsTabReader.script(for: .chromium, bundleID: "com.google.Chrome") == """
                with timeout of 2 seconds
                    tell application id "com.google.Chrome"
                        set theTab to active tab of front window
                        (URL of theTab) & linefeed & (title of theTab)
                    end tell
                end timeout
                """)
    }

    @Test("Reading runs the dialect's script and parses its output")
    func readParsesRunnerOutput() {
        let recorder = RecordingScriptRunner(.success("https://example.com/a\nAn example page"))

        let tab = AppleEventsTabReader.read(
            .chromium, bundleID: "company.thebrowser.dia", runner: recorder.runner)

        #expect(tab == BrowserTab(url: "https://example.com/a", title: "An example page"))
        #expect(
            recorder.sources == [
                AppleEventsTabReader.script(for: .chromium, bundleID: "company.thebrowser.dia")
            ])
    }

    @Test(
        "A failed or empty script is no tab",
        arguments: [
            Result<String?, AppleScriptError>.failure(.automationDenied),
            .failure(.targetNotRunning),
            .success(nil),
            .success(""),
        ])
    func readWithoutOutput(result: Result<String?, AppleScriptError>) {
        let recorder = RecordingScriptRunner(result)
        #expect(
            AppleEventsTabReader.read(
                .safari, bundleID: "com.apple.Safari", runner: recorder.runner)
                == nil)
    }

    @Test("The first line is the URL and the rest is the title")
    func parseSplitsURLAndTitle() {
        let tab = AppleEventsTabReader.parse("https://example.com/a\nAn example page")
        #expect(tab == BrowserTab(url: "https://example.com/a", title: "An example page"))
    }

    @Test("A linefeed in the title cannot corrupt the URL")
    func parseKeepsMultilineTitleWhole() {
        let tab = AppleEventsTabReader.parse("https://example.com/a\nline one\nline two")
        #expect(tab == BrowserTab(url: "https://example.com/a", title: "line one\nline two"))
    }

    @Test("A missing title comes back nil")
    func parseWithoutTitle() {
        #expect(
            AppleEventsTabReader.parse("https://example.com/a\n")
                == BrowserTab(url: "https://example.com/a", title: nil))
        #expect(
            AppleEventsTabReader.parse("https://example.com/a")
                == BrowserTab(url: "https://example.com/a", title: nil))
    }

    @Test("Empty output is not a tab")
    func parseEmptyOutput() {
        #expect(AppleEventsTabReader.parse("") == nil)
        #expect(AppleEventsTabReader.parse("\nA title with no URL") == nil)
    }
}
