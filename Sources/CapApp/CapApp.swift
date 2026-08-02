import AppKit
import CapKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Opens the search window. ⌥⇧Space is the default per decision T7-A —
    /// ⌃⌥Space is taken by macOS input-source switching.
    static let search = Self("search", initial: .init(.space, modifiers: [.option, .shift]))

    /// Captures whatever is in front of the user. Always captures, even on rapid
    /// repeat presses (T6-B); annotation is a click on the HUD toast, never a
    /// second press.
    static let capture = Self("capture", initial: .init(.c, modifiers: [.control, .option]))
}

/// The cap menu-bar app.
///
/// Note: this target builds as a bare SPM executable, which is enough for CI to
/// prove it compiles and links. It will not behave correctly when run directly —
/// a menu-bar app needs an `Info.plist` and a code signature to get an activation
/// policy, a stable bundle identifier, and Accessibility (TCC) grants. Wrapping it
/// in a real `.app` is release-pipeline work (A5/T9).
///
/// The HUD, search window, onboarding, and permission monitoring arrive with the
/// CapApp ticket. This scaffold is the menu-bar shell only.
@main
struct CapApp: App {
    var body: some Scene {
        MenuBarExtra("cap", systemImage: "bookmark") {
            Text("cap \(CapKit.version)")
            Divider()
            Button("Quit cap") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
