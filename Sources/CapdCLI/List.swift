import ArgumentParser
import CapdKit
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the most recent captures.")

    @Option(help: "Maximum number of captures.")
    var limit = QueryParser.defaultLimit

    @OptionGroup var output: OutputOptions

    func run() throws {
        let hits = try SearchService(store: openStore()).search(SearchQuery(limit: limit))
        try emit(hits, as: output.resolved)
        guard !hits.isEmpty else {
            throw CLIError.noResults(output.resolved == .plain ? "No captures yet." : "")
        }
    }
}
