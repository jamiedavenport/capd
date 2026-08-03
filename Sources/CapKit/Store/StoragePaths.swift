import Foundation

/// Every on-disk location cap owns, derived from a single root.
///
/// The root is the only thing that has to change to move cap's data into an app-group
/// container, which a Share Extension or an App Store build would require.
public struct StoragePaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var live: StoragePaths {
        get throws {
            // Env rather than a flag so all three processes — app, agent, CLI — can be
            // pointed at the same alternate root, which is how integration tests isolate.
            if let override = ProcessInfo.processInfo.environment["CAP_DIR"], !override.isEmpty {
                return StoragePaths(root: URL(fileURLWithPath: override, isDirectory: true))
            }
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return StoragePaths(root: support.appendingPathComponent("cap", isDirectory: true))
        }
    }

    public var databaseURL: URL {
        root.appendingPathComponent("cap.sqlite", isDirectory: false)
    }

    public var assetsDirectory: URL {
        root.appendingPathComponent("assets", isDirectory: true)
    }

    public var agentLockURL: URL {
        root.appendingPathComponent("agent.lock", isDirectory: false)
    }

    /// Per-site favicons, keyed by host rather than capture: shared across captures and
    /// never deleted with one.
    public var faviconsDirectory: URL {
        root.appendingPathComponent("favicons", isDirectory: true)
    }

    public func faviconURL(forHost host: String) -> URL {
        faviconsDirectory.appendingPathComponent(
            "\(FaviconPolicy.cacheKey(forHost: host)).png", isDirectory: false)
    }

    /// A sentinel whose modification date records when the site was confirmed to have
    /// no usable favicon, so misses aren't refetched every launch.
    public func faviconMissURL(forHost host: String) -> URL {
        faviconsDirectory.appendingPathComponent(
            "\(FaviconPolicy.cacheKey(forHost: host)).missing", isDirectory: false)
    }

    public func assetURL(forRelativePath path: String) -> URL {
        assetsDirectory.appendingPathComponent(path, isDirectory: false)
    }

    func createDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: faviconsDirectory, withIntermediateDirectories: true)
    }
}
