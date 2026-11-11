import Foundation

package enum Browser: String, CaseIterable, Sendable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case helium = "net.imput.helium"
    case dia = "company.thebrowser.dia"
    case firefox = "org.mozilla.firefox"
    case zen = "app.zen-browser.zen"
    case librewolf = "org.mozilla.librewolf"
    case waterfox = "net.waterfox.waterfox"
    case search = "com.officecommun.search"

    package init?(bundleID: String) {
        self.init(rawValue: bundleID)
    }

    package var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .helium: "Helium"
        case .dia: "Dia"
        case .firefox: "Firefox"
        case .zen: "Zen"
        case .librewolf: "LibreWolf"
        case .waterfox: "Waterfox"
        case .search: "Search"
        }
    }

    package var tabAccess: TabAccess {
        switch self {
        case .safari:
            .appleEvents(.safari)
        case .chrome, .arc, .helium, .dia:
            .appleEvents(.chromium)
        case .firefox, .zen, .librewolf, .waterfox:
            .accessibility(AccessibilityTabOptions(primesTree: true))
        case .search:
            .accessibility(AccessibilityTabOptions(titleFromDescription: true))
        }
    }

    /// Only scriptable browsers can hand over the rendered HTML of the live tab. The
    /// rest have their page bodies fetched over the network.
    package var supportsTabExtraction: Bool {
        switch tabAccess {
        case .appleEvents: true
        case .accessibility: false
        }
    }
}

/// How a browser exposes its active page.
package enum TabAccess: Equatable, Sendable {
    case appleEvents(ScriptDialect)
    case accessibility(AccessibilityTabOptions)
}

/// The AppleScript vocabulary a scriptable browser understands.
package enum ScriptDialect: Equatable, Sendable, CaseIterable {
    case safari
    case chromium
}

package struct AccessibilityTabOptions: Equatable, Sendable {
    /// Gecko builds its web content accessibility tree only once an assistive app asks.
    package var primesTree: Bool
    /// Falls back to the web area's description when it reports no title.
    package var titleFromDescription: Bool

    package init(primesTree: Bool = false, titleFromDescription: Bool = false) {
        self.primesTree = primesTree
        self.titleFromDescription = titleFromDescription
    }
}
