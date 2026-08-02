import ArgumentParser
import CapKit
import Foundation

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search captures.",
        discussion: """
            Query text may also carry inline site:, since:/after:, before:, and until: \
            filters; the flags below win when both are given.
            """)

    @Argument(help: "The search query.")
    var query: [String] = []

    @Option(help: "Only captures from this host or its subdomains.")
    var site: String?

    @Option(help: "Only captures on or after this day (YYYY-MM-DD).")
    var since: String?

    @Option(help: "Only captures on or before this day (YYYY-MM-DD).")
    var until: String?

    @Option(help: "Maximum number of results.")
    var limit = QueryParser.defaultLimit

    @OptionGroup var output: OutputOptions

    func run() throws {
        let parser = QueryParser()
        var parsed = parser.parse(query.joined(separator: " "), limit: limit)

        if let site {
            parsed.site = site.lowercased()
        }
        if let since {
            guard let start = parser.inclusiveDayStart(since) else {
                throw CLIError.badUsage("--since expects a real YYYY-MM-DD day, got '\(since)'.")
            }
            parsed.createdAfter = start
        }
        if let until {
            guard let end = parser.exclusiveDayEnd(until) else {
                throw CLIError.badUsage("--until expects a real YYYY-MM-DD day, got '\(until)'.")
            }
            parsed.createdBefore = end
        }

        let hits = try SearchService(store: openStore()).search(parsed)
        try emit(hits, as: output.resolved)
        guard !hits.isEmpty else {
            throw CLIError.noResults(output.resolved == .plain ? "No results." : "")
        }
    }
}
