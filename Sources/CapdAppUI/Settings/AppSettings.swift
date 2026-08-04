import Foundation
import Observation

/// The app's user-facing switches, persisted through `UserDefaults` so tests can
/// inject a throwaway suite.
@MainActor
@Observable
package final class AppSettings {
    private let defaults: UserDefaults

    package var fetchesPageBodies: Bool {
        didSet { defaults.set(fetchesPageBodies, forKey: Key.fetchesPageBodies) }
    }

    package var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    package var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }
    }

    package var contextualRemindersEnabled: Bool {
        didSet {
            defaults.set(contextualRemindersEnabled, forKey: Key.contextualRemindersEnabled)
            contextualRemindersChanged(contextualRemindersEnabled)
        }
    }

    package var axGrantedBefore: Bool {
        didSet { defaults.set(axGrantedBefore, forKey: Key.axGrantedBefore) }
    }

    package var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) }
    }

    package var latestKnownVersion: String? {
        didSet { defaults.set(latestKnownVersion, forKey: Key.latestKnownVersion) }
    }

    /// Persisted in the capture store rather than `UserDefaults`: the flag must reach
    /// `capd-agent`, a separate process that cannot see the app's defaults. The app seeds
    /// the value from the store at launch and writes back through `saveAutoTags`.
    package var autoTagsCaptures: Bool {
        didSet { saveAutoTags(autoTagsCaptures) }
    }

    /// Injected by the app; the inert default keeps previews and tests store-free.
    @ObservationIgnored package var saveAutoTags: (Bool) -> Void = { _ in }

    /// Persists a request for the background agent to regenerate automatic tags.
    @ObservationIgnored package var requestRetagging: () -> Void = {}

    @ObservationIgnored package var contextualRemindersChanged: (Bool) -> Void = { _ in }

    /// Nil when on-device tagging can run; otherwise why it cannot.
    package var autoTagsUnavailableReason: String?

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoTagsCaptures = true
        contextualRemindersEnabled =
            defaults.object(forKey: Key.contextualRemindersEnabled) as? Bool ?? false
        fetchesPageBodies = defaults.object(forKey: Key.fetchesPageBodies) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        axGrantedBefore = defaults.bool(forKey: Key.axGrantedBefore)
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        latestKnownVersion = defaults.string(forKey: Key.latestKnownVersion)
    }

    private enum Key {
        static let fetchesPageBodies = "fetchesPageBodies"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let checksForUpdates = "checksForUpdates"
        static let contextualRemindersEnabled = "contextualRemindersEnabled"
        static let axGrantedBefore = "axGrantedBefore"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let latestKnownVersion = "latestKnownVersion"
    }
}
