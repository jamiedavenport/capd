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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
        AgentBootstrap.installAgent()
        let state = self.state
        delegate.openURLs = { state.capture(handoffs: $0) }
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Capd \(CapdKit.version)")
            if let failure = state.startupFailure {
                Text(failure)
            }
            if state.failedEnrichmentCount > 0 {
                Text("Failed enrichments: \(state.failedEnrichmentCount)")
            }
            if state.permissions.axLost {
                Button("Accessibility access lost — Open System Settings") {
                    state.permissions.openAccessibilitySettings()
                }
            }
            if let version = state.updates.availableVersion {
                Divider()
                Button("Update available (\(version)) — copy brew command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        UpdateChecker.upgradeCommand, forType: .string)
                }
            }
            Divider()
            Button("Search Captures…") {
                state.showSearch()
            }
            Button(
                state.settings.hasCompletedOnboarding
                    ? "Replay Introduction…"
                    : "Continue Setup…"
            ) {
                state.showOnboarding()
            }
            Divider()
            SettingsLink()
                .keyboardShortcut(",")
            Button("Quit Capd") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
