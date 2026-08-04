import CapdKit
import Foundation

/// What the toast says about one capture attempt.
package struct HUDContent: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case captured
        case duplicate
        case insight
        case copied
        case blocked
        case failed
    }

    var style: Style
    var captureID: Int64?
    var headline: String
    var detail: String?
    var kind: CaptureKind? = nil
    var note: String? = nil
    var host: String? = nil

    var canAnnotate: Bool {
        captureID != nil
    }

    /// The note text to persist when the drawer closes, or nil when there is nothing
    /// to do: an empty field only saves when the capture has a note to clear.
    func noteEdit(from field: String) -> String? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty && note == nil ? nil : trimmed
    }

    package static func outcome(_ outcome: CaptureOutcome, fallbackNote: String?, now: Date)
        -> HUDContent
    {
        let capture = outcome.capture
        let subject = subject(of: capture)
        switch outcome {
        case .captured:
            return HUDContent(
                style: .captured,
                captureID: capture.id,
                headline: fallbackNote == nil ? "Captured" : "Captured link only",
                detail: joined(subject, fallbackNote),
                kind: capture.kind,
                note: capture.note,
                host: capture.kind == .link ? capture.host : nil)
        case .alreadyCaptured(_, let previousSeenAt):
            return HUDContent(
                style: .duplicate,
                captureID: capture.id,
                headline: "Already captured \(relativeDescription(of: previousSeenAt, to: now))",
                detail: joined(subject, fallbackNote),
                kind: capture.kind,
                note: capture.note,
                host: capture.kind == .link ? capture.host : nil)
        }
    }

    package static func copied(_ capture: Capture) -> HUDContent {
        HUDContent(
            style: .copied,
            headline: "Copied to clipboard",
            detail: subject(of: capture),
            kind: capture.kind,
            host: capture.kind == .link ? capture.host : nil)
    }

    package static func previouslySaved(_ capture: Capture, now: Date) -> HUDContent {
        let age = relativeDescription(of: capture.createdAt, to: now)
        let count = capture.seenCount > 1 ? " · seen \(capture.seenCount)×" : ""
        let detail: String?
        if let note = normalizedLine(capture.note) {
            detail = "“\(note)”"
        } else if capture.seenCount > 1 {
            detail = "Last seen \(relativeDescription(of: capture.lastSeenAt, to: now))"
        } else {
            detail = subject(of: capture)
        }
        return HUDContent(
            style: .insight,
            headline: "Saved \(age)\(count)",
            detail: detail,
            kind: capture.kind,
            host: capture.kind == .link ? capture.host : nil)
    }

    package static func blocked() -> HUDContent {
        HUDContent(style: .blocked, headline: "Capture blocked", detail: "Secure input is active.")
    }

    package static func failure(_ error: any Error, detail: String?) -> HUDContent {
        HUDContent(
            style: .failed,
            headline: (error as? any LocalizedError)?.errorDescription ?? "Capture failed",
            detail: detail)
    }

    static func relativeDescription(of date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func subject(of capture: Capture) -> String? {
        capture.title
            ?? capture.host
            ?? capture.url
            ?? capture.selection.map { String($0.prefix(80)) }
            ?? (capture.kind == .image ? "Image from the clipboard" : nil)
    }

    private static func joined(_ parts: String?...) -> String? {
        let joined = parts.compactMap { $0 }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func normalizedLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let line = value.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(120))
    }
}
