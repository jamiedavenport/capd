import Foundation
import FoundationModels

/// The live tagger: Apple's on-device model, so captured content never leaves the Mac.
public struct FoundationModelTagger: Tagger {
    public init() {}

    public func availability() -> TaggerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(.appleIntelligenceOff)
        case .unavailable(.modelNotReady):
            .unavailable(.modelDownloading)
        case .unavailable:
            .unavailable(.unknown)
        }
    }

    public func assignTags(
        _ input: TaggingInput,
        taxonomy: [String],
        mayInventNew: Bool
    ) async throws -> [String] {
        let vocabulary =
            taxonomy.isEmpty
            ? "There are no existing tags yet, so invent fitting ones."
            : "Prefer these existing tags wherever one fits: \(taxonomy.joined(separator: ", "))."
        let invention =
            mayInventNew
            ? "Invent a new tag only when no existing tag fits."
            : "Use only the existing tags; never invent a new one."

        // A fresh session per capture: context accumulates within a session, and the
        // window is small enough that a batch would overflow it.
        let session = LanguageModelSession(
            instructions: """
                You tag saved bookmarks, notes, and screenshots with broad topic tags. \
                A tag is one lowercase word, or two joined by a hyphen. \
                \(vocabulary) \(invention)
                """)

        do {
            let response = try await session.respond(
                to: Prompt(Self.describe(input)),
                generating: TagCandidates.self)
            return response.content.tags
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        }
    }

    public func planTaxonomy(_ samples: [TaggingInput], existing: [String]) async throws -> [String]
    {
        let session = LanguageModelSession(
            instructions: """
                You design the global topic vocabulary for a bookmarking app. Choose a \
                coherent set of at most \(Taxonomy.maxTags) broad, reusable tags that covers \
                the whole sample. Merge overlapping topics and avoid tags that fit only one \
                item. A tag is one lowercase word, or two joined by a hyphen.
                """)
        let current = existing.isEmpty ? "none" : existing.joined(separator: ", ")
        let listing = samples.enumerated().map { index, input in
            "\(index + 1). \(Self.describeForPlanning(input))"
        }.joined(separator: "\n")

        do {
            let response = try await session.respond(
                to: Prompt("Existing tags: \(current)\nRepresentative captures:\n\(listing)"),
                generating: TaxonomyPlan.self)
            return response.content.tags
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        }
    }

    public func reviseTaxonomy(_ usage: [TagUsage]) async throws -> TaxonomyRevision {
        let session = LanguageModelSession(
            instructions: """
                You curate the tag vocabulary of a bookmarking app. Given every tag with \
                its usage, pick the strongest set of at most \(Taxonomy.maxTags) tags: \
                merge synonyms and overlapping topics, fold rare tags into broader kept \
                ones, and drop what cannot be folded. A tag is one lowercase word, or two \
                joined by a hyphen.
                """)

        let listing = usage.map { entry in
            let samples =
                entry.sampleTitles.isEmpty
                ? ""
                : " — e.g. \(entry.sampleTitles.joined(separator: "; "))"
            return "\(entry.tag) (\(entry.count) captures)\(samples)"
        }.joined(separator: "\n")

        do {
            let response = try await session.respond(
                to: Prompt("Current tags:\n\(listing)"),
                generating: RevisionChoice.self)
            return TaxonomyRevision(
                keep: response.content.keep,
                merges: Dictionary(
                    response.content.merges.map { ($0.from, $0.to) },
                    uniquingKeysWith: { first, _ in first }))
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        }
    }

    /// Guardrail refusals and window overflows would recur on retry, so they surface as
    /// ``TaggingError/contentRejected``; anything else is worth retrying later.
    static func mapped(_ error: LanguageModelSession.GenerationError) -> any Error {
        switch error {
        case .guardrailViolation, .exceededContextWindowSize, .refusal,
            .unsupportedLanguageOrLocale:
            TaggingError.contentRejected
        case .assetsUnavailable:
            TaggingError.unavailable
        default:
            error
        }
    }

    private static func describe(_ input: TaggingInput) -> String {
        var lines: [String] = []
        if let title = input.title, !title.isEmpty { lines.append("Title: \(title)") }
        if let host = input.host, !host.isEmpty { lines.append("Site: \(host)") }
        if let note = input.note, !note.isEmpty { lines.append("Note: \(note)") }
        if let selection = input.selection, !selection.isEmpty {
            lines.append("Selected text: \(selection)")
        }
        if let excerpt = input.excerpt, !excerpt.isEmpty { lines.append("Content: \(excerpt)") }
        return lines.isEmpty ? "An untitled capture with no text." : lines.joined(separator: "\n")
    }

    /// Keeps the whole planning prompt comfortably inside the model's small context window.
    /// Titles and sites usually carry the topic; a short excerpt covers untitled captures.
    private static func describeForPlanning(_ input: TaggingInput) -> String {
        var parts: [String] = []
        if let title = input.title, !title.isEmpty { parts.append("Title: \(title)") }
        if let host = input.host, !host.isEmpty { parts.append("Site: \(host)") }
        if let note = input.note, !note.isEmpty { parts.append("Note: \(note.prefix(120))") }
        if let excerpt = input.excerpt, !excerpt.isEmpty {
            parts.append("Excerpt: \(excerpt.prefix(240))")
        }
        return parts.isEmpty ? "Untitled capture" : parts.joined(separator: " | ")
    }
}

@Generable
private struct TagCandidates {
    @Guide(description: "Three candidate topic tags, best first", .count(3))
    var tags: [String]
}

@Generable
private struct TaxonomyPlan {
    @Guide(
        description: "Broad global topic tags, most useful first",
        .maximumCount(Taxonomy.maxTags))
    var tags: [String]
}

@Generable
private struct RevisionChoice {
    @Guide(description: "The tags to keep, at most ten, most important first")
    var keep: [String]
    @Guide(description: "Each removed tag folded into the kept tag that replaces it")
    var merges: [TagMerge]
}

@Generable
private struct TagMerge {
    var from: String
    var to: String
}
