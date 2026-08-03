import Foundation
import Testing

@testable import CapKit

@Suite("FaviconHTML")
struct FaviconHTMLTests {
    private let pageURL = URL(string: "https://example.com/docs/page")!

    @Test("Every icon rel variant is found; mask-icon is not artwork")
    func relVariants() {
        let html = """
            <html><head>
            <link rel="icon" href="/icon.png">
            <link rel="shortcut icon" href="/shortcut.ico">
            <link rel="apple-touch-icon" href="/touch.png">
            <link rel="apple-touch-icon-precomposed" href="/touch-pre.png">
            <link rel="mask-icon" href="/mask.svg" color="#000">
            <link rel="stylesheet" href="/style.css">
            </head><body></body></html>
            """
        let found = FaviconHTML.candidates(in: html, pageURL: pageURL)
        let paths = found.compactMap { $0.url?.path() }
        #expect(paths == ["/icon.png", "/shortcut.ico", "/touch.png", "/touch-pre.png"])
        #expect(found.filter(\.isAppleTouch).count == 2)
    }

    @Test("Relative hrefs resolve against the page URL")
    func relativeResolution() {
        let html = #"<link rel="icon" href="../assets/icon.png">"#
        let found = FaviconHTML.candidates(in: html, pageURL: pageURL)
        #expect(found.first?.url == URL(string: "https://example.com/assets/icon.png"))
    }

    @Test("Declared sizes rank toward the rendered size, apple-touch above unknowns")
    func sizeRanking() {
        let html = """
            <link rel="icon" href="/tiny.png" sizes="16x16">
            <link rel="icon" href="/right.png" sizes="64x64">
            <link rel="icon" href="/huge.png" sizes="512x512">
            <link rel="apple-touch-icon" href="/touch.png">
            <link rel="icon" href="/unknown.png">
            """
        let found = FaviconHTML.candidates(in: html, pageURL: pageURL)
        #expect(FaviconHTML.best(found)?.url?.path() == "/right.png")

        let noRight = found.filter { $0.url?.path() != "/right.png" }
        #expect(FaviconHTML.best(noRight)?.url?.path() == "/touch.png")

        let unknownVersusSmall = found.filter {
            ["/tiny.png", "/unknown.png"].contains($0.url?.path())
        }
        #expect(FaviconHTML.best(unknownVersusSmall)?.url?.path() == "/unknown.png")
    }

    @Test("SVG is kept but flagged, and raster wins at equal rank")
    func svgFlagging() {
        let html = """
            <link rel="icon" href="/icon.svg" type="image/svg+xml">
            <link rel="icon" href="/icon.png">
            """
        let found = FaviconHTML.candidates(in: html, pageURL: pageURL)
        #expect(found.first { $0.url?.path() == "/icon.svg" }?.isSVG == true)
        #expect(FaviconHTML.best(found)?.url?.path() == "/icon.png")
    }

    @Test("A base64 data: href decodes inline")
    func dataURL() {
        let payload = Data("fake-png-bytes".utf8).base64EncodedString()
        let html = #"<link rel="icon" href="data:image/png;base64,\#(payload)">"#
        let found = FaviconHTML.candidates(in: html, pageURL: pageURL)
        #expect(found.first?.inlineData == Data("fake-png-bytes".utf8))
        #expect(found.first?.url == nil)
        #expect(found.first?.isSVG == false)
    }

    @Test("A page with no icons yields nothing")
    func noIcons() {
        let html = "<html><head><title>t</title></head><body>hello</body></html>"
        #expect(FaviconHTML.candidates(in: html, pageURL: pageURL).isEmpty)
        #expect(FaviconHTML.best([]) == nil)
    }
}
