import CapdAppUI
import Foundation

/// Reads a browser's frontmost tab by the route that browser supports.
struct FrontTabReader {
    enum Route {
        /// Apple Events for scriptable browsers, Accessibility for the rest.
        case native
        /// Accessibility for every browser; no Apple Events are sent.
        case accessibilityOnly
    }

    var runner: AppleScriptRunner
    var accessibility: @MainActor (pid_t, AccessibilityTabOptions) async -> BrowserTab?

    static let live = FrontTabReader(
        runner: .live,
        accessibility: { await AccessibilityTabReader.read(processIdentifier: $0, options: $1) })

    @MainActor
    func read(_ browser: Browser, target: FrontmostTarget, route: Route = .native) async
        -> BrowserTab?
    {
        switch (browser.tabAccess, route) {
        case (.appleEvents(let dialect), .native):
            AppleEventsTabReader.read(dialect, bundleID: browser.rawValue, runner: runner)
        case (.appleEvents, .accessibilityOnly):
            await accessibility(target.processIdentifier, AccessibilityTabOptions())
        case (.accessibility(let options), _):
            await accessibility(target.processIdentifier, options)
        }
    }
}
