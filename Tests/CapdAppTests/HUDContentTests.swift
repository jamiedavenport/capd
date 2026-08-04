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

    @Test("A saved-page insight leads with the original note")
    func savedPageShowsNote() {
        let saved = Date(timeIntervalSinceReferenceDate: 1_000)
        let capture = Capture(
            id: 4,
            kind: .link,
            url: "https://example.com/a",
            host: "example.com",
            title: "A page",
            note: "use this for onboarding",
            createdAt: saved)

        let content = HUDContent.previouslySaved(
            capture, now: saved.addingTimeInterval(60 * 60 * 24 * 60))

        #expect(content.style == .insight)
        #expect(content.headline.hasPrefix("Saved "))
        #expect(content.detail == "“use this for onboarding”")
        #expect(content.host == "example.com")
        #expect(!content.canAnnotate)
    }

    @Test("A revisited page shows its count and last visit without a note")
    func savedPageShowsHistory() {
        let saved = Date(timeIntervalSinceReferenceDate: 1_000)
        let capture = Capture(
            id: 4,
            kind: .link,
            url: "https://example.com/a",
            host: "example.com",
            title: "A page",
            createdAt: saved,
            lastSeenAt: saved.addingTimeInterval(60 * 60 * 24 * 20),
            seenCount: 3)

        let content = HUDContent.previouslySaved(
            capture, now: saved.addingTimeInterval(60 * 60 * 24 * 60))

        #expect(content.headline.contains("seen 3×"))
        #expect(content.detail?.hasPrefix("Last seen ") == true)
    }
}
