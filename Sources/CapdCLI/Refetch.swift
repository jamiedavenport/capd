import ArgumentParser
import CapdKit
import Foundation

struct Refetch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Put captures back in the enrichment queue.",
        discussion: """
            With no ids, requeues every capture whose enrichment failed or came back thin. \
            With ids, requeues those captures whatever their last outcome.
            """)

    @Argument(help: "Capture ids. Omit to requeue everything that failed.")
    var ids: [Int64] = []

    func run() throws {
        let store = try openStore()

        guard !ids.isEmpty else {
            let count = try store.requeueFailedCaptures()
            guard count > 0 else { throw CLIError.noResults("Nothing to refetch.") }
            print(summary(count))
            return
        }

        let search = SearchService(store: store)
        let missing = try ids.filter { try search.capture(id: $0) == nil }
        let count = try store.requeueCaptures(ids: ids)
        print(summary(count))
        guard missing.isEmpty else {
            throw CLIError.noResults(describeMissing(missing))
        }
    }

    private func summary(_ count: Int) -> String {
        "Requeued \(count) capture\(count == 1 ? "" : "s")."
    }
}
