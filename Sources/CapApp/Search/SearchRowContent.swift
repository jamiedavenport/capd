import CapKit
import Foundation

/// One result row, flattened out of a hit so the view has nothing left to compute.
struct SearchRowContent: Equatable {
    var kind: CaptureKind
    var title: String
    var subtitle: String?
    var snippet: AttributedString?
    var age: String
    var host: String?
}

extension SearchRowContent {
    init(_ hit: SearchHit, now: Date) {
        let capture = hit.capture
        kind = capture.kind
        title = Self.title(for: capture)
        subtitle = Self.subtitle(for: capture)
        snippet = hit.snippet.map(Self.attributed) ?? Self.preview(of: capture)
        age = Self.compactAge(from: capture.createdAt, to: now)
        host = Self.host(for: capture)
    }

    static func host(for capture: Capture) -> String? {
        guard capture.kind == .link else { return nil }
        return capture.host ?? capture.url.flatMap { URLComponents(string: $0)?.host }
    }

    static func title(for capture: Capture) -> String {
        if let title = capture.title, !title.isEmpty {
            return title
        }
        switch capture.kind {
        case .link:
            return capture.url.map(displayURL) ?? "Link"
        case .text:
            return firstLine(of: capture.selection ?? capture.note ?? capture.body) ?? "Text"
        case .image:
            return "Image"
        }
    }

    static func subtitle(for capture: Capture) -> String? {
        switch capture.kind {
        case .link:
            return capture.url.map(displayURL)
        case .text:
            let length = (capture.selection ?? capture.body ?? capture.note)?.count ?? 0
            return length > 0 ? "text · \(length.formatted()) chars" : "text"
        case .image:
            let indexed = !(capture.ocrText ?? "").isEmpty
            return indexed ? "image · OCR indexed" : "image"
        }
    }

    /// `https://www.sqlite.org/fts5.html` reads as `sqlite.org/fts5.html`: the scheme and
    /// a leading `www.` carry nothing a human scanning rows needs.
    static func displayURL(_ raw: String) -> String {
        guard let components = URLComponents(string: raw), let host = components.host else {
            return raw
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = components.path == "/" ? "" : components.path
        let display = bareHost + path
        return display.isEmpty ? raw : display
    }

    /// Spotlight-dense ages: "now", "5m", "3h", "2d", "3w", "2mo", "1y".
    static func compactAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minute = 60.0
        let hour = 60 * minute
        let day = 24 * hour
        switch seconds {
        case ..<minute: return "now"
        case ..<hour: return "\(Int(seconds / minute))m"
        case ..<day: return "\(Int(seconds / hour))h"
        case ..<(7 * day): return "\(Int(seconds / day))d"
        case ..<(30 * day): return "\(Int(seconds / (7 * day)))w"
        case ..<(365 * day): return "\(Int(seconds / (30 * day)))mo"
        default: return "\(Int(seconds / (365 * day)))y"
        }
    }

    static func attributed(_ snippet: Snippet) -> AttributedString {
        let text = snippet.text
        var result = AttributedString()
        var cursor = text.startIndex
        for range in snippet.highlights.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard range.lowerBound >= cursor else { continue }
            result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            var match = AttributedString(String(text[range]))
            match.inlinePresentationIntent = .stronglyEmphasized
            result.append(match)
            cursor = range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    /// Rows found by substring or recency carry no FTS snippet; a plain body preview keeps
    /// them as scannable as ranked hits. Only a bounded prefix is read — a capture body can
    /// be hundreds of kilobytes, and this runs per row per keystroke.
    static func preview(of capture: Capture) -> AttributedString? {
        guard let source = capture.body ?? capture.selection ?? capture.ocrText ?? capture.note
        else { return nil }
        let collapsed = source.prefix(400)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return AttributedString(String(collapsed.prefix(160)))
    }

    private static func firstLine(of text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(80))
    }
}
