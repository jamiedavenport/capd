import Testing

@testable import CapdApp

@Suite("AccessibilityTabReader")
struct AccessibilityTabReaderTests {
    @Test("Title fallback keeps a nonempty page title first")
    func resolvedTitlePrefersPageTitle() {
        #expect(
            AccessibilityTabReader.resolvedTitle(
                "  Page title  ", accessibilityDescription: "Capture - Capd")
                == "Page title")
    }

    @Test("Title fallback trims whitespace and uses the description")
    func resolvedTitleUsesDescriptionWhenPageTitleIsBlank() {
        #expect(
            AccessibilityTabReader.resolvedTitle(
                "  \n", accessibilityDescription: "  Capture - Capd  ")
                == "Capture - Capd")
    }

    @Test("Title fallback uses a nonempty description when title is missing")
    func resolvedTitleUsesDescriptionWhenTitleIsMissing() {
        #expect(
            AccessibilityTabReader.resolvedTitle(nil, accessibilityDescription: "Capture - Capd")
                == "Capture - Capd")
    }

    @Test("Title fallback is nil when both values are missing or blank")
    func resolvedTitleIsNilWithoutEitherValue() {
        #expect(AccessibilityTabReader.resolvedTitle(nil, accessibilityDescription: nil) == nil)
        #expect(AccessibilityTabReader.resolvedTitle("  ", accessibilityDescription: "\n") == nil)
    }
}
