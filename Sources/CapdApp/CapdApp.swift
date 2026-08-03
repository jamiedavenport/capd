import AppKit
import CapdAppUI
import CapdKit
import SwiftUI

extension NSImage {
    static let menuBarLogo = template("MenuBarIcon")
    static let menuBarLogoSlash = template("MenuBarIconSlash")

    private static func template(_ name: String) -> NSImage {
        let image = Bundle.module.image(forResource: name) ?? NSImage()
        image.isTemplate = true
        return image
    }
}

/// Receives `capd://` opens; SwiftUI's `onOpenURL` needs a window, and a menu-bar
/// app has none to give it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openURLs: (([URL]) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        openURLs?(urls)
    }
}

/// The Capd menu-bar app.
///
/// Building this target produces a bare executable, which is enough to compile and
/// link but not to run: a menu-bar app needs an `Info.plist` and a code signature
/// before it gets an activation policy, a stable bundle identifier, or
/// Accessibility grants.
@main
struct CapdApp: App {
    private static let docsURL = URL(string: "https://capd.jxd.dev")!
    private static let supportURL = URL(string: "https://github.com/jamiedavenport/capd/issues")!
    private static let releaseNotesURL =
        URL(string: "https://github.com/jamiedavenport/capd/releases")!

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
        AgentBootstrap.installAgent()
        let state = self.state
        delegate.openURLs = { state.capture(handoffs: $0) }
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                Label("Capd \(CapdKit.version)", systemImage: "info.circle")
                if let failure = state.startupFailure {
                    Label(failure, systemImage: "exclamationmark.octagon")
                }
                if state.failedEnrichmentCount > 0 {
                    Label(
                        "Failed enrichments: \(state.failedEnrichmentCount)",
                        systemImage: "exclamationmark.triangle")
                }
                if state.permissions.axLost {
                    Button(
                        "Accessibility access lost — Open System Settings",
                        systemImage: "accessibility"
                    ) {
                        state.permissions.openAccessibilitySettings()
                    }
                }
                if let version = state.updates.availableVersion {
                    Divider()
                    Button(
                        "Update available (\(version)) — copy brew command",
                        systemImage: "arrow.down.circle"
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            UpdateChecker.upgradeCommand, forType: .string)
                    }
                }
                Divider()
                Button("Search Captures…", systemImage: "magnifyingglass") {
                    state.showSearch()
                }
                Button("Import from Pinboard…", systemImage: "tray.and.arrow.down") {
                    state.importFromPinboard()
                }
                Button(
                    state.settings.hasCompletedOnboarding
                        ? "Replay Introduction…"
                        : "Continue Setup…",
                    systemImage: state.settings.hasCompletedOnboarding
                        ? "play.circle"
                        : "checklist"
                ) {
                    state.showOnboarding()
                }
                Divider()
                Link(destination: Self.docsURL) {
                    Label("Docs", systemImage: "book.closed")
                }
                Link(destination: Self.supportURL) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                Link(destination: Self.releaseNotesURL) {
                    Label("Release Notes", systemImage: "newspaper")
                }
                Divider()
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                Button("Quit Capd", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .labelStyle(.titleAndIcon)
        } label: {
            switch state.menuBarGlyph {
            case .dropTarget:
                Image(systemName: "plus.circle.fill")
            case .degraded:
                Image(nsImage: .menuBarLogoSlash)
            case .normal:
                Image(nsImage: .menuBarLogo)
            }
        }

        Settings {
            SettingsView(settings: state.settings)
        }
    }
}
