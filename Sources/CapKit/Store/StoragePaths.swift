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

    public func assetURL(forRelativePath path: String) -> URL {
        assetsDirectory.appendingPathComponent(path, isDirectory: false)
    }

    func createDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: assetsDirectory, withIntermediateDirectories: true)
    }
}
