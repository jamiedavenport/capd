import Foundation
import GRDB

public enum CaptureKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case link
    case text
    case image
}

/// ```
///                  ┌──────────────────────────────┐
///                  │                              ▼
///   (new) ──▶ pending ──▶ fetching ──▶ ok │ thin │ failed
///                  ▲          │                   │
///                  └──────────┘                   │
///              crash reclaim / refetch ───────────┘
/// ```
public enum EnrichmentState: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pending
    case fetching
    case ok
    case thin
    case failed

    public var isQueued: Bool {
        self == .pending || self == .fetching
    }

    public func canTransition(to next: EnrichmentState) -> Bool {
        switch (self, next) {
        case (.pending, .fetching), (.pending, .failed):
            true
        case (.fetching, .pending), (.fetching, .ok), (.fetching, .thin), (.fetching, .failed):
            true
        case (.ok, .pending), (.thin, .pending), (.failed, .pending):
            true
        default:
            false
        }
    }
}

public enum BodyStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    /// No body is expected: an image or text capture, or a link captured with `--no-fetch`.
    case none
    case ok
    /// Extraction returned too little to trust, usually a paywall or login wall.
    case thin
    case failed
}

public enum BodySource: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case tab
    case fetch
}

public struct Capture: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var kind: CaptureKind

    public var url: String?
    public var host: String?
    public var title: String?
    public var note: String?
    public var selection: String?
    public var body: String?
    public var ocrText: String?
    /// Relative to ``StoragePaths/assetsDirectory``, so the storage root can move.
    public var assetPath: String?
    public var sourceAppBundleID: String?

    /// Space-joined lowercase tags, nil until the tagging pass has run.
    public var tags: String?
    /// The taxonomy version the tags were assigned under; 0 marks a capture that still
    /// needs tagging, which is what lets nil tags mean "nothing applied" rather than
    /// "not yet processed".
    public var tagsVersion: Int

    public var enrichmentState: EnrichmentState
    public var bodyStatus: BodyStatus
    public var bodySource: BodySource?
    public var attemptCount: Int
    public var lastAttemptAt: Date?

    /// Hash of the normalized URL, or of the content for captures with no URL.
    public var contentHash: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastSeenAt: Date
    public var seenCount: Int

    init(
        id: Int64? = nil,
        kind: CaptureKind,
        url: String? = nil,
        host: String? = nil,
        title: String? = nil,
        note: String? = nil,
        selection: String? = nil,
        body: String? = nil,
        ocrText: String? = nil,
        assetPath: String? = nil,
        sourceAppBundleID: String? = nil,
        tags: String? = nil,
        tagsVersion: Int = 0,
        enrichmentState: EnrichmentState = .pending,
        bodyStatus: BodyStatus = .none,
        bodySource: BodySource? = nil,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        contentHash: String? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        seenCount: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.host = host
        self.title = title
        self.note = note
        self.selection = selection
        self.body = body
        self.ocrText = ocrText
        self.assetPath = assetPath
        self.sourceAppBundleID = sourceAppBundleID
        self.tags = tags
        self.tagsVersion = tagsVersion
        self.enrichmentState = enrichmentState
        self.bodyStatus = bodyStatus
        self.bodySource = bodySource
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastSeenAt = lastSeenAt ?? createdAt
        self.seenCount = seenCount
    }

    public var tagList: [String] {
        tags?.split(separator: " ").map(String.init) ?? []
    }
}

extension Capture: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = Schema.captures

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case kind
        case url
        case host
        case title
        case note
        case selection
        case body
        case ocrText = "ocr_text"
        case assetPath = "asset_path"
        case sourceAppBundleID = "source_app_bundle_id"
        case tags
        case tagsVersion = "tags_version"
        case enrichmentState = "enrichment_state"
        case bodyStatus = "body_status"
        case bodySource = "body_source"
        case attemptCount = "attempt_count"
        case lastAttemptAt = "last_attempt_at"
        case contentHash = "content_hash"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSeenAt = "last_seen_at"
        case seenCount = "seen_count"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
