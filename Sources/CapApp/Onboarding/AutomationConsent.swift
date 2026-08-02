import AppKit
import CoreServices

/// Where a browser stands on cap reading its front tab over Apple Events.
enum AutomationConsentStatus: Equatable {
    case granted
    case denied
    case undetermined
    case notRunning
}

/// Queries and pre-warms the per-app Apple Events consent, so the first real capture
/// isn't interrupted by a TCC dialog.
enum AutomationConsent {
    /// Blocks while the consent dialog is up when `askIfNeeded` is true — call off the
    /// main actor when asking.
    static func status(for browser: Browser, askIfNeeded: Bool) -> AutomationConsentStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.rawValue)
        guard let descriptor = target.aeDesc else { return .undetermined }
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), askIfNeeded)
        switch status {
        case noErr:
            return .granted
        case OSStatus(procNotFound):
            return .notRunning
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .undetermined
        }
    }
}
