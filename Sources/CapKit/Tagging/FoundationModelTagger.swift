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
            .unavailable(reason: "This Mac cannot run Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(reason: "Apple Intelligence is turned off in System Settings.")
        case .unavailable(.modelNotReady):
            .unavailable(reason: "The Apple Intelligence model is still downloading.")
        case .unavailable:
            .unavailable(reason: "Apple Intelligence is unavailable.")
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
    private static func mapped(_ error: LanguageModelSession.GenerationError) -> any Error {
        switch error {
        case .guardrailViolation, .exceededContextWindowSize:
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
}

@Generable
private struct TagCandidates {
    @Guide(description: "Three candidate topic tags, best first", .count(3))
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
