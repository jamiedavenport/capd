import CapdAppUI
import Foundation

enum TabExtractionError: Error, Equatable {
    case unsupportedBrowser(String)
    case automationDenied
    case browserNotRunning
    case emptyResult
    case scriptFailure(String)
}

/// Reads the rendered page out of the frontmost tab of a browser, over Apple Events.
struct TabExtractor {
    static let documentHTMLJavaScript = "document.documentElement.outerHTML"

    static func script(for browser: Browser, javaScript: String) -> String? {
        guard browser.supportsTabExtraction else {
            return nil
        }
        let literal = appleScriptStringLiteral(javaScript)
        let command =
            switch browser {
            case .safari:
                "do JavaScript \"\(literal)\" in current tab of front window"
            case .chrome, .arc:
                "execute active tab of front window javascript \"\(literal)\""
            case .firefox, .zen, .librewolf, .waterfox:
                ""
            }
        return """
            with timeout of 5 seconds
                tell application id "\(browser.rawValue)"
                    \(command)
                end tell
            end timeout
            """
    }

    static func appleScriptStringLiteral(_ javaScript: String) -> String {
        javaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    @MainActor
    func extractHTML(fromBrowserWithBundleID bundleID: String) throws(TabExtractionError)
        -> String
    {
        guard let browser = Browser(bundleID: bundleID),
            let source = Self.script(for: browser, javaScript: Self.documentHTMLJavaScript)
        else {
            throw .unsupportedBrowser(bundleID)
        }
        guard let script = NSAppleScript(source: source) else {
            throw .scriptFailure("script did not compile")
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw Self.extractionError(from: errorInfo)
        }
        guard let html = descriptor.stringValue, !html.isEmpty else {
            throw .emptyResult
        }
        return html
    }

    private static func extractionError(from info: NSDictionary) -> TabExtractionError {
        let number = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        switch number {
        case -1743:
            return .automationDenied
        case -600, -609:
            return .browserNotRunning
        default:
            let message = (info[NSAppleScript.errorMessage] as? String) ?? "error \(number)"
            return .scriptFailure(message)
        }
    }
}
