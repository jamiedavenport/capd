import Foundation
import Testing

@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("HUD actions")
struct HUDActionTests {
    @Test("Performing the reminder action opens its page")
    func reminderActionOpensURL() {
        var opened: [URL] = []
        let controller = HUDPanelController(
            favicons: nil,
            saveNote: { _, _ in },
            openURL: { opened.append($0) })
        let capture = Capture(
            id: 1,
            kind: .link,
            url: "https://example.com/reminder",
            title: "Example",
            createdAt: Date())
        controller.show(.reminder(capture))

        controller.performAction()

        #expect(opened == [URL(string: "https://example.com/reminder")!])
    }
}
