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

    @Test("Unmodified horizontal arrows adjust ratings")
    func horizontalArrowsAdjustRatings() {
        #expect(SearchView.ratingDelta(for: .leftArrow, modifiers: []) == -1)
        #expect(SearchView.ratingDelta(for: .rightArrow, modifiers: []) == 1)
    }

    @Test("Modified horizontal arrows retain text-field behavior")
    func modifiedHorizontalArrowsAreIgnored() {
        #expect(SearchView.ratingDelta(for: .leftArrow, modifiers: [.command]) == nil)
        #expect(SearchView.ratingDelta(for: .rightArrow, modifiers: [.option]) == nil)
        #expect(SearchView.ratingDelta(for: .upArrow, modifiers: []) == nil)
    }
}
