import Foundation
import FoundationModels

public enum LibraryAnswerAvailability: Sendable, Equatable {
    case available
    case unavailable(Reason)

    public enum Reason: Sendable, Equatable {
        case deviceNotEligible
        case appleIntelligenceOff
        case modelDownloading
        case unknown

        public var explanation: String {
            switch self {
            case .deviceNotEligible:
                "This Mac cannot run Apple Intelligence."
            case .appleIntelligenceOff:
                "Apple Intelligence is turned off in System Settings."
            case .modelDownloading:
                "The Apple Intelligence model is still downloading."
            case .unknown:
                "Apple Intelligence is unavailable."
            }
        }
    }
}

public enum LibraryAnswerError: Error, LocalizedError, Equatable {
    case unavailable(LibraryAnswerAvailability.Reason)
    case emptyQuestion
    case noMatches
    case noSupportedClaims
    case contentRejected

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason.explanation
        case .emptyQuestion:
            "Type a question first."
        case .noMatches:
            "No captures matched that question. Try using a specific topic, title, or site."
        case .noSupportedClaims:
            "Cap couldn't build an answer supported by the matching captures."
        case .contentRejected:
            "Apple Intelligence couldn't answer from this content."
        }
    }
}

public struct LibraryAnswer: Codable, Sendable, Equatable {
    public let question: String
    public let passages: [Passage]
    public let sources: [Source]

    public init(question: String, passages: [Passage], sources: [Source]) {
        self.question = question
        self.passages = passages
        self.sources = sources
    }

    public struct Passage: Codable, Sendable, Equatable, Identifiable {
        public let text: String
        /// One-based source numbers, matching ``LibraryAnswer/sources``.
        public let citations: [Int]

        public var id: String { "\(text)|\(citations)" }

        public init(text: String, citations: [Int]) {
            self.text = text
            self.citations = citations
        }
    }

    public struct Source: Codable, Sendable, Equatable, Identifiable {
        public let number: Int
        public let captureID: Int64
        public let kind: CaptureKind
        public let title: String
        public let url: String?
        public let host: String?
        /// The bounded evidence handed to the model, useful to MCP clients for verification.
        public let excerpt: String

        public var id: Int { number }

        public init(
            number: Int,
            captureID: Int64,
            kind: CaptureKind,
            title: String,
            url: String?,
            host: String?,
            excerpt: String
        ) {
            self.number = number
            self.captureID = captureID
            self.kind = kind
            self.title = title
            self.url = url
            self.host = host
            self.excerpt = excerpt
        }
    }
}

struct LibraryAnswerPromptSource: Sendable, Equatable {
    let number: Int
    let title: String
    let location: String
    let excerpt: String
}

struct LibraryAnswerDraft: Sendable, Equatable {
    let statements: [Statement]

    struct Statement: Sendable, Equatable {
        let text: String
        let sourceNumbers: [Int]
    }
}

protocol LibraryAnswerModel: Sendable {
    func availability() -> LibraryAnswerAvailability
    func answer(
        question: String,
        sources: [LibraryAnswerPromptSource]
    ) async throws -> LibraryAnswerDraft
}

/// Retrieves a small, relevant evidence set before asking Apple's on-device model to
/// synthesize it. Retrieval and generation both stay on the Mac.
public struct LibraryAnswerService: Sendable {
    static let sourceLimit = 6
    static let perSearchLimit = 12
    static let excerptLimit = 1_600
    static let totalExcerptLimit = 8_000

    private let search: SearchService
    private let model: any LibraryAnswerModel

    public init(search: SearchService) {
        self.init(search: search, model: FoundationLibraryAnswerModel())
    }

    init(search: SearchService, model: any LibraryAnswerModel) {
        self.search = search
        self.model = model
    }

    public func availability() -> LibraryAnswerAvailability {
        model.availability()
    }

    public func answer(_ rawQuestion: String) async throws -> LibraryAnswer {
        let question = Self.normalizedQuestion(rawQuestion)
        guard !question.isEmpty else { throw LibraryAnswerError.emptyQuestion }
        if case .unavailable(let reason) = model.availability() {
            throw LibraryAnswerError.unavailable(reason)
        }

        let hits = try retrieve(question)
        guard !hits.isEmpty else { throw LibraryAnswerError.noMatches }

        var remaining = Self.totalExcerptLimit
        var sources: [LibraryAnswer.Source] = []
        var prompts: [LibraryAnswerPromptSource] = []
        for hit in hits {
            guard let captureID = hit.capture.id, remaining > 0 else { continue }
            let excerpt = Self.evidence(from: hit, limit: min(Self.excerptLimit, remaining))
            guard !excerpt.isEmpty else { continue }
            remaining -= excerpt.count

            let number = sources.count + 1
            let title = Self.title(for: hit.capture)
            let location = hit.capture.url ?? hit.capture.host ?? "Capture #\(captureID)"
            sources.append(
                .init(
                    number: number,
                    captureID: captureID,
                    kind: hit.capture.kind,
                    title: title,
                    url: hit.capture.url,
                    host: hit.capture.host,
                    excerpt: excerpt))
            prompts.append(
                .init(number: number, title: title, location: location, excerpt: excerpt))
        }
        guard !sources.isEmpty else { throw LibraryAnswerError.noMatches }

        let draft = try await model.answer(question: question, sources: prompts)
        let validNumbers = Set(sources.map(\.number))
        var seenStatements = Set<String>()
        let passages = draft.statements.compactMap { statement -> LibraryAnswer.Passage? in
            let text = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let citations = statement.sourceNumbers.reduce(into: [Int]()) { result, number in
                guard validNumbers.contains(number), !result.contains(number) else { return }
                result.append(number)
            }
            guard
                !text.isEmpty,
                !citations.isEmpty,
                seenStatements.insert(text.lowercased()).inserted
            else { return nil }
            return .init(text: text, citations: citations)
        }
        guard !passages.isEmpty else { throw LibraryAnswerError.noSupportedClaims }

        return LibraryAnswer(question: question, passages: passages, sources: sources)
    }

    /// Natural-language questions contain connective words that make an all-token FTS query
    /// too strict. A combined topic query supplies precision; single-term legs recover recall.
    func retrieve(_ question: String) throws -> [SearchHit] {
        let terms = Self.significantTerms(in: question)
        guard !terms.isEmpty else { return [] }

        struct Candidate {
            var hit: SearchHit
            var score: Double
            var matchedQueries: Int
        }
        var candidates: [Int64: Candidate] = [:]

        func merge(_ hits: [SearchHit], weight: Double) {
            for (rank, hit) in hits.enumerated() {
                guard let id = hit.capture.id else { continue }
                let rankScore = weight / Double(rank + 1)
                if var candidate = candidates[id] {
                    candidate.score += rankScore
                    candidate.matchedQueries += 1
                    candidates[id] = candidate
                } else {
                    candidates[id] = Candidate(hit: hit, score: rankScore, matchedQueries: 1)
                }
            }
        }

        merge(
            try search.search(terms.joined(separator: " "), limit: Self.perSearchLimit),
            weight: 8)
        for term in terms.prefix(8) {
            merge(try search.search(term, limit: Self.perSearchLimit), weight: 2)
        }

        return candidates.values.sorted { lhs, rhs in
            if lhs.matchedQueries != rhs.matchedQueries {
                return lhs.matchedQueries > rhs.matchedQueries
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (lhs.hit.capture.createdAt, lhs.hit.capture.id ?? 0)
                > (rhs.hit.capture.createdAt, rhs.hit.capture.id ?? 0)
        }.prefix(Self.sourceLimit).map(\.hit)
    }

    public static func normalizedQuestion(_ raw: String) -> String {
        var question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.first == "?" {
            question.removeFirst()
            question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return question
    }

    static func significantTerms(in question: String) -> [String] {
        let words = question.lowercased().split { character in
            !character.isLetter && !character.isNumber && character != "-"
        }
        var seen = Set<String>()
        return words.compactMap { raw in
            let word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard word.count > 1, !stopWords.contains(word), seen.insert(word).inserted else {
                return nil
            }
            return word
        }
    }

    private static let stopWords: Set<String> = [
        "about", "all", "also", "an", "and", "are", "as", "at", "be", "but", "by",
        "can", "compare", "did", "do", "does", "everything", "for", "from", "had",
        "has", "have", "how", "i", "in", "into", "is", "it", "me", "my", "of", "on",
        "or", "saved", "show", "source", "sources", "that", "the", "their", "them",
        "there", "these", "this", "to", "was", "were", "what", "when", "where", "which",
        "who", "why", "with",
    ]

    private static func evidence(from hit: SearchHit, limit: Int) -> String {
        let capture = hit.capture
        var parts: [String] = []
        if let title = capture.title, !title.isEmpty { parts.append("Title: \(title)") }
        if let url = capture.url, !url.isEmpty { parts.append("URL: \(url)") }
        if let note = capture.note, !note.isEmpty { parts.append("Note: \(note)") }
        if let selection = capture.selection, !selection.isEmpty {
            parts.append("Selected text: \(selection)")
        }
        if let snippet = hit.snippet?.text, !snippet.isEmpty {
            parts.append("Relevant excerpt: \(snippet)")
        }
        if let body = capture.body ?? capture.ocrText, !body.isEmpty {
            parts.append("Content: \(body)")
        }
        let collapsed = parts.joined(separator: "\n").split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    private static func title(for capture: Capture) -> String {
        if let title = capture.title, !title.isEmpty { return title }
        if let host = capture.host, !host.isEmpty { return host }
        if let url = capture.url, !url.isEmpty { return url }
        switch capture.kind {
        case .link: return "Link"
        case .text: return "Text capture"
        case .image: return "Image capture"
        }
    }
}

/// Apple's system model implementation. A fresh session keeps each question inside the
/// small on-device context window and avoids carrying one library query into the next.
struct FoundationLibraryAnswerModel: LibraryAnswerModel {
    func availability() -> LibraryAnswerAvailability {
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

    func answer(
        question: String,
        sources: [LibraryAnswerPromptSource]
    ) async throws -> LibraryAnswerDraft {
        let session = LanguageModelSession(
            instructions: """
                Answer questions using only the numbered sources supplied by a private \
                capture library. Every statement must be directly supported by at least \
                one source. Cite the source numbers that support each statement. Never use \
                outside knowledge, invent a source, or claim more than the excerpts show. \
                If sources disagree, describe the disagreement. Do not repeat a statement. \
                Be concise and direct.
                """)
        let sourceText = sources.map { source in
            """
            [\(source.number)] \(source.title)
            Location: \(source.location)
            \(source.excerpt)
            """
        }.joined(separator: "\n\n")

        do {
            let response = try await session.respond(
                to: Prompt("Question: \(question)\n\nSources:\n\(sourceText)"),
                generating: GeneratedLibraryAnswer.self)
            return LibraryAnswerDraft(
                statements: response.content.statements.map {
                    .init(text: $0.text, sourceNumbers: $0.sourceNumbers)
                })
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                throw LibraryAnswerError.contentRejected
            case .assetsUnavailable:
                throw LibraryAnswerError.unavailable(.unknown)
            case .exceededContextWindowSize:
                throw LibraryAnswerError.noSupportedClaims
            default:
                throw error
            }
        }
    }
}

@Generable
private struct GeneratedLibraryAnswer {
    @Guide(description: "Concise supported statements, in the best order to answer the question")
    var statements: [GeneratedLibraryStatement]
}

@Generable
private struct GeneratedLibraryStatement {
    @Guide(description: "One or two sentences containing a claim supported by the cited sources")
    var text: String
    @Guide(description: "The one-based numbers of every supplied source supporting this statement")
    var sourceNumbers: [Int]
}
