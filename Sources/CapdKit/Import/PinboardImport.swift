import Foundation

/// One bookmark from a Pinboard JSON export (Settings → Backup → JSON on pinboard.in).
public struct PinboardPost: Decodable, Sendable, Equatable {
    public var href: String
    public var description: String?
    public var extended: String?
    public var tags: String?
    public var time: String?
    public var toread: String?

    public init(
        href: String,
        description: String? = nil,
        extended: String? = nil,
        tags: String? = nil,
        time: String? = nil,
        toread: String? = nil
    ) {
        self.href = href
        self.description = description
        self.extended = extended
        self.tags = tags
        self.time = time
        self.toread = toread
    }
}

public enum PinboardImportError: Error, Equatable, Sendable {
    case notAPinboardExport
}

extension PinboardImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAPinboardExport:
            "Not a Pinboard JSON export — expected an array of bookmark objects."
        }
    }
}

public struct PinboardImportSummary: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let href: String
        public let message: String
    }

    public var imported = 0
    public var merged = 0
    public var failures: [Failure] = []

    public init() {}
}

/// Replays a Pinboard JSON export through ``CaptureService``, so an imported bookmark
/// is deduplicated and stored exactly like any other capture.
public struct PinboardImporter: Sendable {
    private let captures: CaptureService

    public init(captures: CaptureService) {
        self.captures = captures
    }

    /// Imports every bookmark it can and reports the rest as failures; one bad row
    /// must not abort a multi-thousand-bookmark run.
    public func run(data: Data, now: Date = Date()) throws -> PinboardImportSummary {
        let posts = try Self.posts(from: data)
        var summary = PinboardImportSummary()

        for post in posts {
            do {
                switch try captures.ingest(Self.request(for: post, now: now)) {
                case .captured:
                    summary.imported += 1
                case .alreadyCaptured:
                    summary.merged += 1
                }
            } catch {
                let message =
                    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                summary.failures.append(.init(href: post.href, message: message))
            }
        }
        return summary
    }

    public static func posts(from data: Data) throws -> [PinboardPost] {
        guard let posts = try? JSONDecoder().decode([PinboardPost].self, from: data) else {
            throw PinboardImportError.notAPinboardExport
        }
        return posts
    }

    /// Pinboard's `description` is the bookmark title, and `extended` is the user's note.
    /// `toread` becomes a `toread` tag — the model has no read-later flag, and a tag keeps
    /// the list recoverable. An unparseable `time` falls back to `now` rather than costing
    /// the bookmark itself. `shared` has no equivalent and is dropped.
    static func request(for post: PinboardPost, now: Date = Date()) -> CaptureRequest {
        var tags = (post.tags ?? "").split(separator: " ").map(String.init)
        if post.toread == "yes" {
            tags.append("toread")
        }
        return CaptureRequest(
            url: post.href,
            title: nonBlank(post.description),
            note: nonBlank(post.extended),
            tags: tags,
            // Terminal on arrival: a bulk import must not flood the enrichment queue.
            fetchBody: false,
            capturedAt: post.time.flatMap { try? Date($0, strategy: .iso8601) } ?? now)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
