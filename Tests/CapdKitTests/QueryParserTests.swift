import Foundation
import Testing

@testable import CapdKit

@Suite("Search query parsing")
struct QueryParserTests {
    @Test(
        "Filter tokens leave the search text",
        arguments: [
            ("site:GitHub.com rust", "rust", "github.com"),
            ("SITE:example.com", "", "example.com"),
            ("rust site:example.com traits", "rust traits", "example.com"),
            ("site:a.com site:b.com", "", "b.com"),
            ("  site:example.com   ", "", "example.com"),
            ("site:example.com/path", "", "example.com/path"),
        ])
    func siteExtraction(input: String, text: String, site: String) {
        let query = parser.parse(input)

        #expect(query.text == text)
        #expect(query.site == site)
    }

    @Test(
        "tag: tokens leave the search text",
        arguments: [
            ("tag:swift", "", "swift"),
            ("TAG:Swift notes", "notes", "swift"),
            ("tag:#swift", "", "swift"),
            ("tag:a tag:b", "", "b"),
        ])
    func tagExtraction(input: String, text: String, tag: String) {
        let query = parser.parse(input)

        #expect(query.text == text)
        #expect(query.tag == tag)
    }

    @Test(
        "Anything that is not a filter stays in the text",
        arguments: [
            "plain words",
            "site:",
            "title:foo",
            "https://example.com/a",
            "after:2026-13-01",
            "after:2026-02-30",
            "after:26-01-01",
            "since:2026-1-1",
            "until:yesterday",
            "before:",
            "tag:",
            "tag:##",
            ":leading",
        ])
    func nonFiltersStayInText(input: String) {
        let query = parser.parse(input)

        #expect(query.text == input.trimmingCharacters(in: .whitespaces))
        #expect(query.site == nil)
        #expect(query.tag == nil)
        #expect(query.createdAfter == nil)
        #expect(query.createdBefore == nil)
    }

    @Test("after: and since: are the same inclusive lower bound")
    func lowerBoundKeywords() {
        let expected = date(2026, 3, 14)

        #expect(parser.parse("after:2026-03-14").createdAfter == expected)
        #expect(parser.parse("SINCE:2026-03-14").createdAfter == expected)
        #expect(parser.parse("after:2026-03-14 notes").text == "notes")
    }

    @Test("before: excludes its day and until: includes it")
    func upperBoundKeywords() {
        #expect(parser.parse("before:2026-03-14").createdBefore == date(2026, 3, 14))
        #expect(parser.parse("until:2026-03-14").createdBefore == date(2026, 3, 15))
    }

    @Test("The day-boundary helpers are what the CLI flags bind to")
    func dayBoundaryHelpers() {
        #expect(parser.inclusiveDayStart("2026-01-01") == date(2026, 1, 1))
        #expect(parser.exclusiveDayEnd("2026-01-01") == date(2026, 1, 2))
        #expect(parser.inclusiveDayStart("2024-02-29") == date(2024, 2, 29))
        #expect(parser.exclusiveDayEnd("2024-02-28") == date(2024, 2, 29))
        #expect(parser.inclusiveDayStart("2023-02-29") == nil)
        #expect(parser.inclusiveDayStart("2026-1-1") == nil)
        #expect(parser.inclusiveDayStart("") == nil)
        #expect(parser.exclusiveDayEnd("nonsense") == nil)
    }

    @Test("Digits outside ASCII are not a date")
    func nonASCIIDigitsAreRejected() {
        #expect(parser.inclusiveDayStart("٢٠٢٦-٠١-٠١") == nil)
        #expect(parser.exclusiveDayEnd("٢٠٢٦-٠١-٠١") == nil)
        #expect(parser.parse("after:٢٠٢٦-٠١-٠١").createdAfter == nil)
        #expect(parser.parse("after:٢٠٢٦-٠١-٠١").text == "after:٢٠٢٦-٠١-٠١")
    }

    @Test("A last-wins date filter replaces the earlier one")
    func repeatedDateFilters() {
        let query = parser.parse("after:2026-01-01 after:2026-06-01")

        #expect(query.createdAfter == date(2026, 6, 1))
        #expect(query.text.isEmpty)
    }

    @Test("Filters combine into one query")
    func combinedFilters() {
        let query = parser.parse("site:example.com since:2026-01-01 until:2026-01-31 sqlite wal")

        #expect(query.text == "sqlite wal")
        #expect(query.site == "example.com")
        #expect(query.createdAfter == date(2026, 1, 1))
        #expect(query.createdBefore == date(2026, 2, 1))
    }

    @Test("Whitespace collapses and an empty query stays empty")
    func whitespaceHandling() {
        #expect(parser.parse("  a \n b \t c ").text == "a b c")
        #expect(parser.parse("").text.isEmpty)
        #expect(parser.parse("   ").text.isEmpty)
    }

    @Test("The limit rides along on the parsed query")
    func limitPassesThrough() {
        #expect(parser.parse("anything").limit == QueryParser.defaultLimit)
        #expect(parser.parse("anything", limit: 7).limit == 7)
    }
}

private let parser = QueryParser(calendar: utcCalendar)

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}
