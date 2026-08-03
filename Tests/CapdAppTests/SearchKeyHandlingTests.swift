import SwiftUI
import Testing

@testable import CapdAppUI

@MainActor
@Suite("Search key handling")
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
}
