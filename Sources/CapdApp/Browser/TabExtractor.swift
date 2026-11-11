import CapdAppUI
import Foundation

enum TabExtractionError: Error, Equatable {
    case unsupportedBrowser(Browser)
    case emptyResult
    case script(AppleScriptError)
}

/// Reads the rendered page out of the frontmost tab of a browser, over Apple Events.
struct TabExtractor: Sendable {
    static let documentHTMLJavaScript = "document.documentElement.outerHTML"

    var runner: AppleScriptRunner = .live

    static func script(for dialect: ScriptDialect, bundleID: String, javaScript: String) -> String {
        let literal = AppleScriptRunner.stringLiteral(javaScript)
        let command =
            switch dialect {
            case .safari:
                "do JavaScript \"\(literal)\" in current tab of front window"
            case .chromium:
                "execute active tab of front window javascript \"\(literal)\""
            }
        return AppleScriptRunner.tell(bundleID: bundleID, timeoutSeconds: 5, command)
    }

    @MainActor
    func extractHTML(from browser: Browser) throws(TabExtractionError) -> String {
        guard case .appleEvents(let dialect) = browser.tabAccess else {
            throw .unsupportedBrowser(browser)
        }
        let source = Self.script(
            for: dialect, bundleID: browser.rawValue, javaScript: Self.documentHTMLJavaScript)
        let html: String?
        do {
            html = try runner.run(source)
        } catch {
            throw .script(error)
        }
        guard let html, !html.isEmpty else {
            throw .emptyResult
        }
        return html
    }
}
