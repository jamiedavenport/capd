import AppKit
import SwiftUI
import Testing

@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("Search key handling", .serialized)
struct SearchKeyHandlingTests {
    @Test("Arrows move the selection and Return opens it")
    func arrowsAndReturnOpenSelection() async throws {
        var opened: [URL] = []
        let model = try await makeModel(openURL: { opened.append($0) })

        #expect(model.handleKey(try keyEvent(.downArrow)))
        #expect(model.isCaptureSelected(1))
        #expect(model.handleKey(try keyEvent(.upArrow)))
        #expect(model.isCaptureSelected(0))
        #expect(model.handleKey(try keyEvent(.downArrow)))
        #expect(model.handleKey(try keyEvent(.carriageReturn)))
        #expect(opened == [URL(string: "https://example.com/2")])
    }

    @Test("Command-Return copies the selection")
    func commandReturnCopiesSelection() async throws {
        var copied: [String] = []
        let model = try await makeModel(copyText: { copied.append($0) })

        #expect(model.handleKey(try keyEvent(.carriageReturn, modifiers: .command)))
        #expect(copied == ["https://example.com/1"])
    }

    @Test("Tab cycles tags forward, Shift-Tab backward in both macOS representations")
    func tabCyclesTags() async throws {
        let model = try await makeModel(tags: ["a", "b"])

        #expect(model.handleKey(try keyEvent(.tab)))
        #expect(model.activeTag == "a")
        #expect(model.handleKey(try keyEvent(.tab, modifiers: .shift)))
        #expect(model.activeTag == nil)
        #expect(model.handleKey(try keyEvent(.backTab)))
        #expect(model.activeTag == "b")
    }

    @Test("Other keys stay with the query field")
    func unrelatedKeyIsIgnored() async throws {
        let model = try await makeModel()
        #expect(!model.handleKey(try keyEvent(.leftArrow)))
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

    private func makeModel(
        tags: [String] = [],
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        copyText: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> SearchModel {
        let hits = (1...2).map { id in
            SearchHit(
                capture: Capture(
                    id: Int64(id), kind: .link, url: "https://example.com/\(id)",
                    title: "Example \(id)", createdAt: Date()),
                snippet: nil, score: nil)
        }
        let model = SearchModel(
            environment: SearchEnvironment(
                search: { _ in hits },
                totalCount: { hits.count },
                tags: { tags },
                delete: { _ in },
                openURL: openURL,
                copyText: copyText,
                assetFileURL: { _ in nil },
                showHUD: { _ in }))
        model.activate()
        model.queryText = "example"
        await model.settle()
        return model
    }

    private func keyEvent(
        _ key: NSEvent.SpecialKey, modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        let character = String(Character(UnicodeScalar(key.rawValue)!))
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
    }
}
