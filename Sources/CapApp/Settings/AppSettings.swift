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
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        latestKnownVersion = defaults.string(forKey: Key.latestKnownVersion)
    }

    private enum Key {
        static let fetchesPageBodies = "fetchesPageBodies"
        static let checksForUpdates = "checksForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let latestKnownVersion = "latestKnownVersion"
    }
}
