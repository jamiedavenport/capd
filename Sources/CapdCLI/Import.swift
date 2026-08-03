import ArgumentParser
import CapdKit
import Foundation

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Import bookmarks exported from another service.",
        subcommands: [Pinboard.self])

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

extension Import {
    struct Pinboard: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import a Pinboard JSON export.",
            discussion: """
                Reads the JSON backup from pinboard.in (Settings → Backup → JSON). \
                Bookmarks keep their titles, notes, tags, and timestamps; links already \
                in the library merge instead of duplicating, so re-running an import is \
                safe.
                """)

        @Argument(help: "Path to the export file, or '-' to read standard input.")
        var file: String

        func run() throws {
            let store = try openStore()
            let importer = PinboardImporter(captures: CaptureService(store: store))

            let summary: PinboardImportSummary
            do {
                summary = try importer.run(data: try readData())
            } catch let error as PinboardImportError {
                throw CLIError.badUsage(describe(error))
            }

            print("Imported \(summary.imported) new, merged \(summary.merged) existing.")
            for failure in summary.failures {
                printToStderr("Skipped \(failure.href): \(failure.message)")
            }
            if !summary.failures.isEmpty {
                throw CLIError(message: "", code: 2)
            }
        }

        private func readData() throws -> Data {
            if file == "-" {
                return (try? FileHandle.standardInput.readToEnd()) ?? Data()
            }
            do {
                return try Data(contentsOf: URL(fileURLWithPath: file))
            } catch {
                throw CLIError.badUsage("Cannot read \(file): \(describe(error))")
            }
        }
    }
}
