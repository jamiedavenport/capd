import CapdAppUI
import Foundation

/// A browser's frontmost tab, as reported by the browser itself.
struct BrowserTab: Equatable, Sendable {
    var url: String
    var title: String?
}

/// Reads the frontmost tab's URL and title over Apple Events.
enum BrowserTabReader {
    static func script(for browser: Browser) -> String? {
        let tab: String
        let titleProperty: String
        switch browser {
        case .safari:
            tab = "current tab of front window"
            titleProperty = "name"
        case .chrome, .arc:
            tab = "active tab of front window"
            titleProperty = "title"
        case .firefox, .zen, .librewolf, .waterfox:
            return nil
        }
        return """
            with timeout of 2 seconds
                tell application id "\(browser.rawValue)"
                    set theTab to \(tab)
                    (URL of theTab) & linefeed & (\(titleProperty) of theTab)
                end tell
            end timeout
            """
    }

    /// The URL rides the first line so a linefeed in the tab title cannot corrupt it.
    static func parse(_ output: String) -> BrowserTab? {
        let pieces = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            !first.isEmpty
        else { return nil }
        let title =
            pieces.count > 1
            ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return BrowserTab(url: first, title: title.isEmpty ? nil : title)
    }

    @MainActor
    static func read(_ browser: Browser) -> BrowserTab? {
        guard let source = script(for: browser), let script = NSAppleScript(source: source) else {
            return nil
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let output = descriptor.stringValue else { return nil }
        return parse(output)
    }
}
