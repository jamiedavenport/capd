import CapdAppUI
import CapdKit
import Foundation
import Observation

/// Fetches the latest released tag, a closure so tests stub the network.
struct ReleaseClient: Sendable {
    var latestTag: @Sendable () async throws -> String
}

extension ReleaseClient {
    static let gitHubReleases = ReleaseClient {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/jamiedavenport/capd/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
            }
        }
        return try JSONDecoder().decode(Release.self, from: data).tagName
    }
}

/// Numeric dotted ordering for release tags.
enum ReleaseVersion {
    /// Whether `tag` names a strictly newer version than `current`. A leading `v` is
    /// ignored; a non-numeric component counts as 0, so a prerelease tag never flags.
    static func isNewer(tag: String, than current: String) -> Bool {
        let lhs = components(of: tag)
        let rhs = components(of: current)
        for index in 0..<Swift.max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// The passive update check: at most one Releases request a week, none while the
/// setting is off. The newest tag persists in settings, so a found update outlives
/// restarts and clears itself once the running version catches up.
@MainActor
@Observable
final class UpdateChecker {
    static let upgradeCommand = "brew upgrade jamiedavenport/tap/capd"
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    private let settings: AppSettings
    private let client: ReleaseClient
    private let now: @MainActor () -> Date

    init(
        settings: AppSettings,
        client: ReleaseClient,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.settings = settings
        self.client = client
        self.now = now
    }

    var availableVersion: String? {
        guard let latest = settings.latestKnownVersion,
            ReleaseVersion.isNewer(tag: latest, than: CapdKit.version)
        else {
            return nil
        }
        return latest
    }

    func checkIfDue() async {
        guard settings.checksForUpdates else { return }
        if let last = settings.lastUpdateCheck, now().timeIntervalSince(last) < Self.interval {
            return
        }
        // A failure leaves `lastUpdateCheck` alone: an offline pass retries on the
        // next one instead of going quiet for a week.
        guard let tag = try? await client.latestTag() else { return }
        settings.latestKnownVersion = tag
        settings.lastUpdateCheck = now()
    }
}
