import Foundation

/// The global tag vocabulary every capture is tagged against. One row in the database;
/// `capd-agent` is its only writer apart from the enabled flag, which the app toggles.
public struct Taxonomy: Sendable, Equatable {
    public static let maxTags = 10

    /// Bumped only when consolidation rewrites existing assignments. Appending a new tag
    /// leaves it alone, because assignments made under the old list stay valid.
    public var version: Int
    /// At most ``maxTags``, ordered by importance.
    public var tags: [String]
    public var taggedSinceConsolidation: Int
    public var taggingEnabled: Bool
    public var updatedAt: Date

    public init(
        version: Int = 1,
        tags: [String] = [],
        taggedSinceConsolidation: Int = 0,
        taggingEnabled: Bool = true,
        updatedAt: Date
    ) {
        self.version = version
        self.tags = tags
        self.taggedSinceConsolidation = taggedSinceConsolidation
        self.taggingEnabled = taggingEnabled
        self.updatedAt = updatedAt
    }
}
