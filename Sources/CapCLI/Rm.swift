import ArgumentParser
import CapKit
import Foundation

struct Rm: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete captures by id.")

    @Argument(help: "Capture ids, as shown by list and search.")
    var ids: [Int64]

    func run() throws {
        let deleted = try openStore().deleteCaptures(ids: ids)
        for capture in deleted {
            print("Removed #\(capture.id ?? 0): \(headline(capture))")
        }

        let deletedIDs = Set(deleted.compactMap(\.id))
        let missing = ids.filter { !deletedIDs.contains($0) }
        guard missing.isEmpty else {
            throw CLIError.noResults(describeMissing(missing))
        }
    }
}

func describeMissing(_ ids: [Int64]) -> String {
    let listed = ids.map { "#\($0)" }.joined(separator: ", ")
    return ids.count == 1 ? "No capture \(listed)." : "No captures \(listed)."
}
