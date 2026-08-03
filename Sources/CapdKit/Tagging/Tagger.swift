import Foundation

/// What a capture offers the tagger: its capture-time metadata and a bounded excerpt of
/// the enriched text, because the on-device model's context window is small.
public struct TaggingInput: Sendable, Equatable {
    public static let excerptLimit = 1500

    public let title: String?
    public let host: String?
    public let note: String?
    public let selection: String?
    public let excerpt: String?

    public init(_ capture: Capture) {
        title = capture.title
        host = capture.host
        note = capture.note
        selection = capture.selection
        excerpt = (capture.body ?? capture.ocrText).map {
            String($0.prefix(Self.excerptLimit))
        }
    }
}

public enum TaggerAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

public enum TaggingError: Error, Equatable {
    /// The model refused this content; retrying would refuse again, so the capture
    /// should be marked processed rather than requeued.
    case contentRejected
    case unavailable
}

/// Assigns tags to captures and revises the taxonomy. Injectable, like
/// ``FaviconFetcher``'s transport, so tests never load a model.
public protocol Tagger: Sendable {
    func availability() -> TaggerAvailability

    /// Candidate tags for one capture, best first. Callers validate against the
    /// taxonomy; implementations are free to return tags outside it.
    func assignTags(
        _ input: TaggingInput,
        taxonomy: [String],
        mayInventNew: Bool
    ) async throws -> [String]

    /// A revised taxonomy given how the current one is being used.
    func reviseTaxonomy(_ usage: [TagUsage]) async throws -> TaxonomyRevision
}

/// The consolidation outcome: the tags to keep and the renames that fold everything
/// else into them.
public struct TaxonomyRevision: Sendable, Equatable {
    public let keep: [String]
    /// Old tag → surviving tag. Tags in neither `keep` nor here are dropped, and the
    /// captures that carried only dropped tags are re-tagged from scratch.
    public let merges: [String: String]

    public init(keep: [String], merges: [String: String]) {
        self.keep = keep
        self.merges = merges
    }
}
