import Foundation

enum Browser: String, CaseIterable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case firefox = "org.mozilla.firefox"
    case zen = "app.zen-browser.zen"
    case librewolf = "org.mozilla.librewolf"
    case waterfox = "net.waterfox.waterfox"

    init?(bundleID: String) {
        self.init(rawValue: bundleID)
    }

    /// Gecko speaks no Apple Events beyond the basics: the tab URL comes over
    /// Accessibility instead, and the body over the network fetch.
    var isGecko: Bool {
        switch self {
        case .safari, .chrome, .arc: false
        case .firefox, .zen, .librewolf, .waterfox: true
        }
    }

    var supportsTabExtraction: Bool {
        !isGecko
    }
}
