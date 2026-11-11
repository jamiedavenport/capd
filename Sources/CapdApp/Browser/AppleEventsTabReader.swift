import CapdAppUI
import Foundation

/// Reads the frontmost tab's URL and title over Apple Events.
enum AppleEventsTabReader {
    static func script(for dialect: ScriptDialect, bundleID: String) -> String {
        let tab: String
        let titleProperty: String
        switch dialect {
        case .safari:
            tab = "current tab of front window"
            titleProperty = "name"
        case .chromium:
            tab = "active tab of front window"
            titleProperty = "title"
        }
        return AppleScriptRunner.tell(
            bundleID: bundleID, timeoutSeconds: 2,
            """
            set theTab to \(tab)
            (URL of theTab) & linefeed & (\(titleProperty) of theTab)
            """)
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
    static func read(
        _ dialect: ScriptDialect, bundleID: String, runner: AppleScriptRunner = .live
    ) -> BrowserTab? {
        guard let output = try? runner.run(script(for: dialect, bundleID: bundleID)) else {
            return nil
        }
        return parse(output)
    }
}
