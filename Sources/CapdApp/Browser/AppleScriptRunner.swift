import Foundation

enum AppleScriptError: Error, Equatable {
    case automationDenied
    case targetNotRunning
    case failure(String)

    init(errorInfo: NSDictionary) {
        let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        switch number {
        case -1743:
            self = .automationDenied
        case -600, -609:
            self = .targetNotRunning
        default:
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "error \(number)"
            self = .failure(message)
        }
    }
}

/// Compiles and runs AppleScript source, returning the result as text.
struct AppleScriptRunner: Sendable {
    var run: @MainActor @Sendable (_ source: String) throws(AppleScriptError) -> String?

    static let live = AppleScriptRunner { source throws(AppleScriptError) in
        guard let script = NSAppleScript(source: source) else {
            throw .failure("script did not compile")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw AppleScriptError(errorInfo: errorInfo)
        }
        return descriptor.stringValue
    }

    /// Wraps `body` so it addresses one app and gives up rather than hang on a busy one.
    static func tell(bundleID: String, timeoutSeconds: Int, _ body: String) -> String {
        let indented =
            body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "        \($0)" }
            .joined(separator: "\n")
        return """
            with timeout of \(timeoutSeconds) seconds
                tell application id "\(bundleID)"
            \(indented)
                end tell
            end timeout
            """
    }

    static func stringLiteral(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
