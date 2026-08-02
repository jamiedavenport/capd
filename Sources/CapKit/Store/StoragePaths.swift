import Foundation

/// Every on-disk location cap owns, derived from a single root.
///
/// The root is the only thing that has to change to move cap's data into an app-group
/// container, which a Share Extension or an App Store build would require.
public struct StoragePaths: Sendable, Equatable {
    /// The directory holding the database and its assets.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/cap/`.
    public static var live: StoragePaths {
        get throws {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return StoragePaths(root: support.appendingPathComponent("cap", isDirectory: true))
        }
    }

    /// The SQLite database, alongside its `-wal` and `-shm` siblings.
    public var databaseURL: URL {
        root.appendingPathComponent("cap.sqlite", isDirectory: false)
    }

    /// Captured images, content-addressed. `Capture.assetPath` is relative to this.
    public var assetsDirectory: URL {
        root.appendingPathComponent("assets", isDirectory: true)
    }

    /// Resolves a `Capture.assetPath` into an absolute location.
    public func assetURL(forRelativePath path: String) -> URL {
        assetsDirectory.appendingPathComponent(path, isDirectory: false)
    }

    func createDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: assetsDirectory, withIntermediateDirectories: true)
    }
}
