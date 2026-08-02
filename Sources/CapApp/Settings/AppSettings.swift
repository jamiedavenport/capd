import Foundation
import Observation

/// The app's user-facing switches, persisted through `UserDefaults` so tests can
/// inject a throwaway suite.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var fetchesPageBodies: Bool {
        didSet { defaults.set(fetchesPageBodies, forKey: Key.fetchesPageBodies) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }
    }

    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) }
    }

    var latestKnownVersion: String? {
        didSet { defaults.set(latestKnownVersion, forKey: Key.latestKnownVersion) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fetchesPageBodies = defaults.object(forKey: Key.fetchesPageBodies) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        latestKnownVersion = defaults.string(forKey: Key.latestKnownVersion)
    }

    private enum Key {
        static let fetchesPageBodies = "fetchesPageBodies"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let checksForUpdates = "checksForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let latestKnownVersion = "latestKnownVersion"
    }
}
