import AppKit
import CapKit
import KeyboardShortcuts
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

extension KeyboardShortcuts.Name {
    // ⌃⌥Space is reserved by macOS for input-source switching.
    static let search = Self("search", initial: .init(.space, modifiers: [.option, .shift]))

    static let capture = Self("capture", initial: .init(.c, modifiers: [.control, .option]))

    static let annotate = Self("annotate", initial: .init(.n, modifiers: [.control, .option]))
}

/// The cap menu-bar app.
///
/// Building this target produces a bare executable, which is enough to compile and
/// link but not to run: a menu-bar app needs an `Info.plist` and a code signature
/// before it gets an activation policy, a stable bundle identifier, or
/// Accessibility grants.
@main
struct CapApp: App {
    @State private var state = AppState()

    init() {
        AgentBootstrap.installAgent()
    }

    var body: some Scene {
        MenuBarExtra {
            Text("cap \(CapKit.version)")
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
            Divider()
            SettingsLink()
                .keyboardShortcut(",")
            Button("Quit cap") {
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
