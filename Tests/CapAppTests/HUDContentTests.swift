import Foundation
import Testing

@testable import CapApp

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
}
