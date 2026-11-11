import Foundation
import Testing

@testable import CapdApp

@MainActor
final class RecordingScriptRunner {
    var result: Result<String?, AppleScriptError>
    private(set) var sources: [String] = []

    init(_ result: Result<String?, AppleScriptError>) {
        self.result = result
    }

    var runner: AppleScriptRunner {
        AppleScriptRunner { [self] source throws(AppleScriptError) in
            sources.append(source)
            return try result.get()
        }
    }
}

@MainActor
@Suite("AppleScriptRunner")
struct AppleScriptRunnerTests {
    @Test("A script's result comes back as text")
    func liveRunnerReturnsText() throws {
        #expect(try AppleScriptRunner.live.run(#""cap" & "d""#) == "capd")
    }

    @Test("A refused Apple Event surfaces as denied automation")
    func liveRunnerMapsDeniedAutomation() {
        #expect(throws: AppleScriptError.automationDenied) {
            try AppleScriptRunner.live.run(#"error "not allowed" number -1743"#)
        }
    }

    @Test("A script error carries its message")
    func liveRunnerCarriesMessage() {
        #expect(throws: AppleScriptError.failure("boom")) {
            try AppleScriptRunner.live.run(#"error "boom" number 42"#)
        }
    }

    @Test("Source that does not compile is a failure")
    func liveRunnerRejectsBadSource() {
        #expect(throws: AppleScriptError.self) {
            try AppleScriptRunner.live.run("tell tell tell")
        }
    }

    @Test(
        "Error numbers map to cases",
        arguments: [
            (-1743, AppleScriptError.automationDenied),
            (-600, .targetNotRunning),
            (-609, .targetNotRunning),
            (-1728, .failure("error -1728")),
        ])
    func errorNumbers(number: Int, expected: AppleScriptError) {
        let info: NSDictionary = [NSAppleScript.errorNumber: number]
        #expect(AppleScriptError(errorInfo: info) == expected)
    }

    @Test("A tell block addresses one app under a timeout")
    func tellBlock() {
        #expect(
            AppleScriptRunner.tell(bundleID: "com.example.app", timeoutSeconds: 3, "one\ntwo")
                == """
                with timeout of 3 seconds
                    tell application id "com.example.app"
                        one
                        two
                    end tell
                end timeout
                """)
    }

    @Test("Text survives the trip into an AppleScript string literal")
    func stringLiteralEscaping() {
        #expect(
            AppleScriptRunner.stringLiteral(#"a "quoted" \path"#)
                == #"a \"quoted\" \\path"#)
        #expect(
            AppleScriptRunner.stringLiteral("line one\nline\ttwo\r")
                == #"line one\nline\ttwo\r"#)
        #expect(
            AppleScriptRunner.stringLiteral(TabExtractor.documentHTMLJavaScript)
                == TabExtractor.documentHTMLJavaScript)
    }
}
