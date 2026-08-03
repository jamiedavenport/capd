import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdKit

@Suite("HUDContent")
struct HUDContentTests {
    @Test("A typed note is trimmed and saved")
    func noteEditSavesTrimmed() {
        let content = HUDContent(style: .captured, captureID: 1, headline: "Captured")

        #expect(content.noteEdit(from: "  ship it  ") == "ship it")
    }

    @Test("An empty field with no prior note saves nothing")
    func noteEditSkipsEmpty() {
        let content = HUDContent(style: .captured, captureID: 1, headline: "Captured")

        #expect(content.noteEdit(from: "   ") == nil)
    }

    @Test("An empty field clears a prior note")
    func noteEditClearsPriorNote() {
        let content = HUDContent(
            style: .duplicate, captureID: 1, headline: "Already captured", note: "old thought")

        #expect(content.noteEdit(from: "") == "")
    }

    @Test("Editing a prior note replaces it")
    func noteEditReplacesPriorNote() {
        let content = HUDContent(
            style: .duplicate, captureID: 1, headline: "Already captured", note: "old thought")

        #expect(content.noteEdit(from: "new thought") == "new thought")
    }

    @Test("A copied toast names the page and offers no note")
    func copiedNamesThePage() {
        let capture = Capture(
            id: 4,
            kind: .link,
            url: "https://example.com/a",
            host: "example.com",
            title: "A page",
            createdAt: Date(timeIntervalSince1970: 1_000_000))

        let content = HUDContent.copied(capture)

        #expect(content.style == .copied)
        #expect(content.headline == "Copied to clipboard")
        #expect(content.detail == "A page")
        #expect(content.host == "example.com")
        #expect(!content.canAnnotate)
    }
}
