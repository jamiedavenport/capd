import Foundation
import GRDB

/// What a capture holds, decided by pasteboard precedence: URL beats text beats image.
public enum CaptureKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case link
    case text
    case image
}

/// How far a capture has moved through the enrichment queue.
///
/// ```
///                  ┌──────────────────────────────┐
///                  │                              ▼
///   (new) ──▶ pending ──▶ fetching ──▶ ok │ thin │ failed
///                  ▲          │                   │
///                  └──────────┘                   │
///              crash reclaim / refetch ───────────┘
/// ```
///
/// `pending` and `fetching` are the queue; the rest are terminal until something asks for a
/// retry. `fetching → pending` is the reclaim a crashed agent performs on startup, and
/// `ok`/`thin`/`failed → pending` is `cap refetch`.
public enum EnrichmentState: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pending
    case fetching
    case ok
    case thin
    case failed

    /// Whether the row is waiting on, or claimed by, the enrichment agent.
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

/// The verdict on body extraction alone, which outlives the enrichment job that produced it.
///
/// Separate from ``EnrichmentState`` because enrichment does more than fetch a body: an image
/// capture is enriched by OCR and has no body at all, and a link whose fetch failed still needs
/// to record a finished job with an unusable body. `cap refetch` selects on this column;
/// the queue selects on ``EnrichmentState``.
public enum BodyStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    /// No body is expected — an image or text capture, or a link captured with `--no-fetch`.
    case none
    case ok
    /// Extraction returned something, but too little to trust — usually a paywall or login wall.
    case thin
    case failed
}

/// Which of the two extraction paths produced the body.
///
/// Recorded so the tab-first path and the network fallback can be measured against each other.
public enum BodySource: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    /// Read from a live browser tab, so logged-in and post-JS content is included.
    case tab
    /// Refetched over the network as an anonymous client.
    case fetch
}

/// One captured item.
public struct Capture: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var kind: CaptureKind

    public var url: String?
    /// The URL's host, split out so it can be ranked and filtered on its own.
    public var host: String?
    public var title: String?
    /// The user's annotation.
    public var note: String?
    /// The text the user had highlighted at capture time.
    public var selection: String?
    /// Extracted page body for a link, or the captured text itself for a text capture.
    public var body: String?
    public var ocrText: String?
    /// Relative to ``StoragePaths/assetsDirectory``, so the storage root can move.
    public var assetPath: String?
    /// Bundle identifier of the app the capture came from.
    public var sourceApp: String?

    public var enrichmentState: EnrichmentState
    public var bodyStatus: BodyStatus
    public var bodySource: BodySource?
    public var attemptCount: Int
    public var lastAttemptAt: Date?

    /// Hash of the normalized URL, or of the content for captures with no URL. Re-capturing a
    /// matching hash bumps ``lastSeenAt`` and ``seenCount`` instead of inserting a second row.
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
        sourceApp: String? = nil,
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
        self.sourceApp = sourceApp
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
        case sourceApp = "source_app"
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
