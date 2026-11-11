import Testing

@testable import CapdAppUI

@Suite("Browser")
struct BrowserTests {
    @Test(
        "Bundle ids map to browsers exactly",
        arguments: [
            ("com.apple.Safari", Browser.safari),
            ("com.google.Chrome", Browser.chrome),
            ("company.thebrowser.Browser", Browser.arc),
            ("net.imput.helium", Browser.helium),
            ("company.thebrowser.dia", Browser.dia),
            ("org.mozilla.firefox", Browser.firefox),
            ("app.zen-browser.zen", Browser.zen),
            ("org.mozilla.librewolf", Browser.librewolf),
            ("net.waterfox.waterfox", Browser.waterfox),
            ("com.officecommun.search", Browser.search),
        ])
    func bundleIDsMapExactly(bundleID: String, expected: Browser) {
        #expect(Browser(bundleID: bundleID) == expected)
    }

    @Test(
        "Unknown apps are not browsers",
        arguments: ["com.apple.SAFARI", "com.microsoft.edgemac", "com.apple.dt.Xcode", ""])
    func unknownBundleIDsAreRefused(bundleID: String) {
        #expect(Browser(bundleID: bundleID) == nil)
    }

    @Test(
        "Each browser exposes its tab one way",
        arguments: [
            (Browser.safari, TabAccess.appleEvents(.safari)),
            (.chrome, .appleEvents(.chromium)),
            (.arc, .appleEvents(.chromium)),
            (.helium, .appleEvents(.chromium)),
            (.dia, .appleEvents(.chromium)),
            (.firefox, .accessibility(AccessibilityTabOptions(primesTree: true))),
            (.zen, .accessibility(AccessibilityTabOptions(primesTree: true))),
            (.librewolf, .accessibility(AccessibilityTabOptions(primesTree: true))),
            (.waterfox, .accessibility(AccessibilityTabOptions(primesTree: true))),
            (.search, .accessibility(AccessibilityTabOptions(titleFromDescription: true))),
        ])
    func tabAccess(browser: Browser, expected: TabAccess) {
        #expect(browser.tabAccess == expected)
    }

    @Test("Only scriptable browsers support tab extraction")
    func tabExtractionFollowsAccess() {
        #expect(
            Browser.allCases.filter(\.supportsTabExtraction)
                == [.safari, .chrome, .arc, .helium, .dia])
    }
}
