import Foundation

package enum Browser: String, CaseIterable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case helium = "net.imput.helium"
    case firefox = "org.mozilla.firefox"
    case zen = "app.zen-browser.zen"
    case librewolf = "org.mozilla.librewolf"
    case waterfox = "net.waterfox.waterfox"
    case search = "com.officecommun.search"

    package init?(bundleID: String) {
        self.init(rawValue: bundleID)
    }

    /// Gecko browsers and Search expose the active page through Accessibility rather
    /// than Apple Events. Their page bodies are fetched over the network because
    /// they do not support extracting rendered HTML from the live tab.
    package var usesAccessibilityTabReader: Bool {
        switch self {
        case .safari, .chrome, .arc, .helium: false
        case .firefox, .zen, .librewolf, .waterfox, .search: true
        }
    }

    /// Gecko builds its web content accessibility tree only once an assistive app asks.
    package var isGecko: Bool {
        switch self {
        case .firefox, .zen, .librewolf, .waterfox: true
        case .safari, .chrome, .arc, .helium, .search: false
        }
    }

    package var supportsTabExtraction: Bool {
        switch self {
        case .safari, .chrome, .arc, .helium: true
        case .firefox, .zen, .librewolf, .waterfox, .search: false
        }
    }
}
