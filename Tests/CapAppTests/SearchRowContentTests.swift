import Foundation
import Testing

@testable import CapApp
@testable import CapAppUI
@testable import CapKit

@Suite("Search row content")
struct SearchRowContentTests {
    static let ages: [(seconds: Double, expected: String)] = [
        (30, "now"),
        (5 * 60, "5m"),
        (3 * 3600, "3h"),
        (2 * 86400, "2d"),
        (21 * 86400, "3w"),
        (61 * 86400, "2mo"),
        (500 * 86400, "1y"),
    ]

    @Test("Ages render Spotlight-dense", arguments: ages)
    func compactAges(seconds: Double, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let age = SearchRowContent.compactAge(from: now.addingTimeInterval(-seconds), to: now)
        #expect(age == expected)
    }

    @Test("Display URLs drop the scheme, www, and a bare trailing slash")
    func displayURLs() {
        #expect(
            SearchRowContent.displayURL("https://www.sqlite.org/fts5.html")
                == "sqlite.org/fts5.html")
        #expect(SearchRowContent.displayURL("https://example.com/") == "example.com")
        #expect(SearchRowContent.displayURL("not a url") == "not a url")
    }

    @Test("Untitled captures fall back by kind")
    func titleFallbacks() {
        let link = makeCapture(kind: .link, url: "https://www.example.com/a")
        #expect(SearchRowContent.title(for: link) == "example.com/a")

        let text = makeCapture(kind: .text, selection: "  first line\nsecond line")
        #expect(SearchRowContent.title(for: text) == "first line")

        let image = makeCapture(kind: .image)
        #expect(SearchRowContent.title(for: image) == "Image")
    }

    @Test("Subtitles describe the capture, not the query")
    func subtitles() {
        let link = makeCapture(kind: .link, url: "https://www.example.com/a/b")
        #expect(SearchRowContent.subtitle(for: link) == "example.com/a/b")

        let text = makeCapture(kind: .text, selection: String(repeating: "x", count: 340))
        #expect(SearchRowContent.subtitle(for: text) == "text · 340 chars")

        let plainImage = makeCapture(kind: .image)
        #expect(SearchRowContent.subtitle(for: plainImage) == "image")

        let ocrImage = makeCapture(kind: .image, ocrText: "whiteboard")
        #expect(SearchRowContent.subtitle(for: ocrImage) == "image · OCR indexed")
    }

    @Test("Only link rows carry a favicon host, parsed from the URL when unset")
    func hostFlattening() {
        let stored = makeCapture(kind: .link, url: "https://www.example.com/a", host: "example.com")
        #expect(SearchRowContent.host(for: stored) == "example.com")

        let parsed = makeCapture(kind: .link, url: "https://docs.example.com/a")
        #expect(SearchRowContent.host(for: parsed) == "docs.example.com")

        #expect(SearchRowContent.host(for: makeCapture(kind: .text, selection: "x")) == nil)
        #expect(SearchRowContent.host(for: makeCapture(kind: .image)) == nil)
    }

    @Test("Snippet highlights become emphasized runs")
    func snippetEmphasis() {
        let text = "the fts5 module provides fts search"
        let first = text.range(of: "fts5")!
        let second = text.range(of: "fts", range: first.upperBound..<text.endIndex)!
        let snippet = Snippet(text: text, highlights: [first, second])

        let attributed = SearchRowContent.attributed(snippet)

        #expect(String(attributed.characters) == text)
        let emphasized = attributed.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(attributed.characters[$0.range]) }
        #expect(emphasized == ["fts5", "fts"])
    }

    @Test("Rows without a snippet preview the body, whitespace collapsed")
    func bodyPreview() {
        let capture = makeCapture(
            kind: .link, url: "https://example.com/a",
            body: "  The pager\n\n  works like this  ")
        let preview = SearchRowContent.preview(of: capture)
        #expect(preview.map { String($0.characters) } == "The pager works like this")

        #expect(SearchRowContent.preview(of: makeCapture(kind: .image)) == nil)
    }
}

private func makeCapture(
    kind: CaptureKind,
    url: String? = nil,
    host: String? = nil,
    title: String? = nil,
    selection: String? = nil,
    body: String? = nil,
    ocrText: String? = nil
) -> Capture {
    Capture(
        kind: kind,
        url: url,
        host: host,
        title: title,
        selection: selection,
        body: body,
        ocrText: ocrText,
        createdAt: Date(timeIntervalSince1970: 1_000_000))
}
