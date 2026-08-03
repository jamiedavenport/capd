/// Where Capd's share extension stands in the macOS share sheet.
package enum ShareExtensionStatus: Equatable {
    case enabled
    /// The user switched it off in System Settings — an explicit choice onboarding
    /// offers to reverse but never overrides on its own.
    case disabled
    /// Registered with no election either way; onboarding can safely turn it on.
    case defaulted
    /// macOS hasn't discovered the extension, usually because the app has not yet
    /// run from /Applications.
    case unregistered
}
