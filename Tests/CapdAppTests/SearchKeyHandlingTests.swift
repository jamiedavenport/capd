import AppKit
import SwiftUI
import Testing

@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("Search key handling", .serialized)
struct SearchKeyHandlingTests {
    @Test("Tab cycles tags forward")
    func tabCyclesForward() {
        #expect(SearchView.tagCycleForward(for: .tab, modifiers: []) == true)
    }

    @Test("Shift-Tab cycles tags backward in both macOS representations")
    func shiftTabCyclesBackward() {
        #expect(SearchView.tagCycleForward(for: .tab, modifiers: [.shift]) == false)
        #expect(
            SearchView.tagCycleForward(
                for: KeyEquivalent(Character("\u{19}")), modifiers: [.shift]) == false)
    }

    @Test("Unrelated keys are ignored by tag cycling")
    func unrelatedKeyIsIgnored() {
        #expect(SearchView.tagCycleForward(for: .return, modifiers: []) == nil)
    }

    @Test("Command-number rates while the search field has focus")
    func commandNumberRatesFromSearchField() async throws {
        let capture = Capture(
            id: 1,
            kind: .link,
            url: "https://example.com",
            title: "Example",
            rating: 3,
            createdAt: Date())
        let hit = SearchHit(capture: capture, snippet: nil, score: nil)
        var recordedRating: Int?
        let model = SearchModel(
            environment: SearchEnvironment(
                search: { _ in [hit] },
                totalCount: { 1 },
                setRating: { _, rating in recordedRating = rating },
                delete: { _ in },
                openURL: { _ in },
                copyText: { _ in },
                assetFileURL: { _ in nil },
                showHUD: { _ in }))
        model.queryText = "example"
        await model.settle()

        let hosting = NSHostingView(rootView: SearchView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.firstResponder is NSTextView)

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "5",
                charactersIgnoringModifiers: "5",
                isARepeat: false,
                keyCode: 23))

        #expect(window.performKeyEquivalent(with: event))
        #expect(recordedRating == 5)
        window.orderOut(nil)
    }

    @Test("Command-R opens the reminder picker for the selected capture")
    func commandROpensReminderPicker() async throws {
        let capture = Capture(
            id: 1,
            kind: .link,
            url: "https://example.com",
            title: "Example",
            createdAt: Date())
        let hit = SearchHit(capture: capture, snippet: nil, score: nil)
        let model = SearchModel(
            environment: SearchEnvironment(
                search: { _ in [hit] },
                totalCount: { 1 },
                delete: { _ in },
                openURL: { _ in },
                copyText: { _ in },
                assetFileURL: { _ in nil },
                showHUD: { _ in }))
        model.queryText = "example"
        await model.settle()

        let hosting = NSHostingView(rootView: SearchView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)
        try await Task.sleep(for: .milliseconds(50))

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: 15))

        #expect(window.performKeyEquivalent(with: event))
        #expect(model.reminderCapture?.id == 1)
        window.orderOut(nil)
    }
}
