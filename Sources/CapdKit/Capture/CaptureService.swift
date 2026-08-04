import Foundation

public enum CaptureError: Error, Equatable, Sendable {
    case emptyRequest
    case invalidURL(String)
    case secureInputActive
    case notFound(Int64)
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyRequest: "Nothing to capture."
        case .invalidURL(let candidate): "Not a capturable link: \(candidate)"
        case .secureInputActive: "Capture blocked — secure input active."
        case .notFound(let id): "No capture with id \(id)."
        }
    }
}

/// A veto on a capture, consulted before the request is read or anything is written.
public protocol CaptureGuard: Sendable {
    func check(_ request: CaptureRequest) throws
}

/// The one path by which a capture comes into existence.
public struct CaptureService: Sendable {
    let store: Store
    let guards: [any CaptureGuard]

    public init(store: Store, guards: [any CaptureGuard] = []) {
        self.store = store
        self.guards = guards
    }

    public func ingest(_ request: CaptureRequest) throws -> CaptureOutcome {
        for captureGuard in guards {
            try captureGuard.check(request)
        }

        let classification = try Self.classify(request)
        return try store.upsertCapture(makeCapture(classification, from: request))
    }

    /// Sets the user's note on an existing capture; an empty or whitespace note clears it.
    @discardableResult
    public func annotate(_ id: Int64, note: String?) throws -> Capture {
        try store.updateNote(id: id, note: Self.normalized(note))
    }

    private enum Classification {
        case link(URL, selection: String?)
        case text(String)
        case image(Data)
    }

    private static func classify(_ request: CaptureRequest) throws -> Classification {
        let selection = normalized(request.text)

        if let candidate = normalized(request.url) {
            guard let url = URL(string: candidate),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                let host = url.host(), !host.isEmpty
            else {
                throw CaptureError.invalidURL(candidate)
            }
            return .link(url, selection: selection)
        }
        if let selection {
            return .text(selection)
        }
        if let imageData = request.imageData, !imageData.isEmpty {
            return .image(imageData)
        }
        throw CaptureError.emptyRequest
    }

    private func makeCapture(
        _ classification: Classification,
        from request: CaptureRequest
    ) throws -> Capture {
        let tags = Self.pinnedTags(request.tags)
        let tagsVersion = tags == nil ? 0 : Capture.pinnedTagsVersion

        switch classification {
        case .link(let url, let selection):
            return Capture(
                kind: .link,
                url: url.absoluteString,
                host: url.host()?.lowercased(),
                title: request.title,
                note: request.note,
                selection: selection,
                sourceAppBundleID: request.sourceAppBundleID,
                tags: tags,
                tagsVersion: tagsVersion,
                // A link captured with no fetch is born terminal, and `ok -> pending` stays a
                // legal transition so a later refetch can put it back in the queue.
                enrichmentState: request.fetchBody ? .pending : .ok,
                contentHash: CaptureIdentity.contentHash(for: url),
                createdAt: request.capturedAt
            )

        case .text(let text):
            return Capture(
                kind: .text,
                title: request.title,
                note: request.note,
                // The selection column, not the body: bm25 weights it at 2, and `body` means
                // an extracted page.
                selection: text,
                sourceAppBundleID: request.sourceAppBundleID,
                tags: tags,
                tagsVersion: tagsVersion,
                enrichmentState: .ok,
                contentHash: CaptureIdentity.contentHash(for: Data(text.utf8)),
                createdAt: request.capturedAt
            )

        case .image(let imageData):
            let digest = CaptureIdentity.contentHash(for: imageData)
            return Capture(
                kind: .image,
                title: request.title,
                note: request.note,
                assetPath: try writeAsset(imageData, digest: digest),
                sourceAppBundleID: request.sourceAppBundleID,
                tags: tags,
                tagsVersion: tagsVersion,
                enrichmentState: .pending,
                contentHash: digest,
                createdAt: request.capturedAt
            )
        }
    }

    /// Content-addressed, so re-ingesting the same bytes rewrites one file rather than
    /// orphaning the last one.
    private func writeAsset(_ imageData: Data, digest: String) throws -> String {
        let relativePath = "\(digest.prefix(2))/\(digest).png"
        let url = store.paths.assetURL(forRelativePath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageData.write(to: url, options: .atomic)
        return relativePath
    }

    /// Request tags folded to the stored shape, or nil when none survive — the same
    /// normalization the agent's tags go through, so one grammar covers both.
    private static func pinnedTags(_ raw: [String]) -> String? {
        var tags: [String] = []
        for candidate in raw {
            guard let tag = TagService.normalize(candidate), !tags.contains(tag) else { continue }
            tags.append(tag)
        }
        return tags.isEmpty ? nil : tags.joined(separator: " ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
