import AppKit
import CapKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    // ⌃⌥Space is reserved by macOS for input-source switching.
    static let search = Self("search", initial: .init(.space, modifiers: [.option, .shift]))

    static let capture = Self("capture", initial: .init(.c, modifiers: [.control, .option]))
}

/// The cap menu-bar app.
///
/// Building this target produces a bare executable, which is enough to compile and
/// link but not to run: a menu-bar app needs an `Info.plist` and a code signature
/// before it gets an activation policy, a stable bundle identifier, or
/// Accessibility grants.
@main
struct CapApp: App {
    init() {
        AgentBootstrap.installAgent()
    }

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
