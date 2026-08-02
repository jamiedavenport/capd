import AppKit

/// The app the user was looking at when they pressed the capture hotkey.
struct FrontmostTarget: Equatable {
    var bundleID: String?
    var name: String?
    var processIdentifier: pid_t

    @MainActor
    static func current() -> FrontmostTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostTarget(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            processIdentifier: app.processIdentifier)
    }
}
