import Foundation

/// Assigns tags to captures after enrichment and keeps the taxonomy within bounds.
///
/// Unlike the enrichment pipeline this is store-aware and single-writer by design:
/// only the process holding the agent lock should call the mutating methods, which is
/// what makes the plain `tags_version = 0` scan safe without a claim protocol.
public struct TagService: Sendable {
    public static let defaultBatch = 3
    public static let maxTagsPerCapture = 3

    private let store: Store
    private let tagger: any Tagger

    public init(store: Store, tagger: any Tagger) {
        self.store = store
        self.tagger = tagger
    }

    /// Tags up to `batch` untagged captures, returning how many were processed. Returns
    /// 0 without touching the model when tagging is off or the model is unavailable —
    /// the rows keep `tags_version = 0` and are picked up whenever it comes back.
    @discardableResult
    public func tagNext(batch: Int = TagService.defaultBatch, now: Date = Date()) async throws
        -> Int
    {
        guard tagger.availability() == .available else { return 0 }
        var taxonomy = try store.taxonomy()
        guard taxonomy.taggingEnabled else { return 0 }

        let candidates = try store.untaggedCaptures(limit: batch)
        var processed = 0
        for capture in candidates {
            guard let id = capture.id else { continue }
            let mayInvent = taxonomy.tags.count < Taxonomy.maxTags

            let accepted: [String]
            do {
                let raw = try await tagger.assignTags(
                    TaggingInput(capture), taxonomy: taxonomy.tags, mayInventNew: mayInvent)
                accepted = Self.accept(raw, into: &taxonomy, mayInventNew: mayInvent)
            } catch let error as TaggingError where error == .contentRejected {
                // Retrying would be refused again, so the capture is marked processed
                // with no tags rather than left to hot-loop in the queue.
                accepted = []
            }

            taxonomy.taggedSinceConsolidation += 1
            taxonomy.updatedAt = now
            try store.completeTagging(id: id, tags: accepted, taxonomy: taxonomy, now: now)
            processed += 1
        }
        return processed
    }

    /// Filters the model's candidates down to trustworthy tags: normalized, deduplicated,
    /// inside the taxonomy — growing it only while there is room — and capped per capture.
    /// The model is never trusted to obey the closed set on its own.
    static func accept(
        _ candidates: [String],
        into taxonomy: inout Taxonomy,
        mayInventNew: Bool
    ) -> [String] {
        var accepted: [String] = []
        for candidate in candidates {
            guard accepted.count < maxTagsPerCapture else { break }
            guard let tag = normalize(candidate), !accepted.contains(tag) else { continue }
            if taxonomy.tags.contains(tag) {
                accepted.append(tag)
            } else if mayInventNew && taxonomy.tags.count < Taxonomy.maxTags {
                taxonomy.tags.append(tag)
                accepted.append(tag)
            }
        }
        return accepted
    }

    /// One lowercase word, or words joined by hyphens; anything else is folded into that
    /// shape or discarded. Tags are stored space-joined, so a space can never survive.
    static func normalize(_ raw: String) -> String? {
        let folded = raw.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
        var collapsed = ""
        for character in folded {
            let mapped: Character? =
                if character.isWhitespace || character == "-" {
                    "-"
                } else if character.isASCII && (character.isLetter || character.isNumber) {
                    character
                } else {
                    nil
                }
            guard let mapped else { continue }
            if mapped == "-" && (collapsed.isEmpty || collapsed.hasSuffix("-")) { continue }
            collapsed.append(mapped)
        }
        while collapsed.hasSuffix("-") { collapsed.removeLast() }
        guard !collapsed.isEmpty, collapsed.count <= 30 else { return nil }
        return collapsed
    }
}
