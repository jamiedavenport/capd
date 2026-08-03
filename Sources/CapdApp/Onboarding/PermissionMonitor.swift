import Observation

/// Everything the monitor reads or pokes, injectable so loss detection tests without
/// TCC state or live `UserDefaults`.
struct PermissionMonitorEnvironment {
    var isAXTrusted: @MainActor () -> Bool
    var wasGrantedBefore: @MainActor () -> Bool
    var setWasGrantedBefore: @MainActor (Bool) -> Void
    var openAXSettings: @MainActor () -> Void
}

/// Detects a previously granted Accessibility grant going stale.
///
/// TCC keys the grant to the app's code signature, so a certificate rotation or a
/// dev-to-release swap silently revokes access while the app keeps launching normally.
/// The monitor remembers that access was granted once and flags the check where it
/// comes back false, so the app can prompt for a re-grant instead of degrading silently.
@MainActor
@Observable
final class PermissionMonitor {
    private let environment: PermissionMonitorEnvironment
    var onLoss: (() -> Void)?

    private(set) var axLost = false

    init(environment: PermissionMonitorEnvironment) {
        self.environment = environment
    }

    func check() {
        if environment.isAXTrusted() {
            if !environment.wasGrantedBefore() {
                environment.setWasGrantedBefore(true)
            }
            axLost = false
        } else if environment.wasGrantedBefore(), !axLost {
            axLost = true
            onLoss?()
        }
    }

    func openAccessibilitySettings() {
        environment.openAXSettings()
    }
}
