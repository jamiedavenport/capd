import Foundation

/// The raw payload handed to ``CaptureService/ingest(_:)``, before it is classified.
///
/// `url` is a `String` rather than a `URL` because every caller starts with one — CLI
/// arguments, pasteboard items, a browser's tab title — and deciding whether it is a usable
/// link is ingest's job.
public struct CaptureRequest: Sendable, Equatable {
    public var url: String?
    /// The selection accompanying `url`, or the whole content when there is no `url`.
    public var text: String?
    /// PNG bytes.
    public var imageData: Data?
    public var title: String?
    public var note: String?
    /// Tags the capturer already has — a Pinboard import keeping the user's own tags.
    /// Stored pinned, so the tagging pass neither reassigns nor consolidates them.
    public var tags: [String]
    public var sourceAppBundleID: String?
    public var fetchBody: Bool
    public var capturedAt: Date

    public init(
        url: String? = nil,
        text: String? = nil,
        imageData: Data? = nil,
        title: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        sourceAppBundleID: String? = nil,
        fetchBody: Bool = true,
        capturedAt: Date = Date()
    ) {
        self.url = url
        self.text = text
        self.imageData = imageData
        self.title = title
        self.note = note
        self.tags = tags
        self.sourceAppBundleID = sourceAppBundleID
        self.fetchBody = fetchBody
        self.capturedAt = capturedAt
    }
}
