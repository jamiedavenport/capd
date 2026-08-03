import ArgumentParser
import CapdKit
import Darwin
import Foundation

/// The `capd` command-line interface.
struct Capd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capd",
        abstract: "Capture and recall anything you have seen.",
        version: CapdKit.version,
        subcommands: [
            Add.self, Search.self, List.self, Rm.self, Import.self, Export.self,
            Refetch.self, Status.self, Doctor.self, Mcp.self,
        ]
    )

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

/// Hand-rolled entry point because ArgumentParser exits with sysexits codes, and the CLI
/// contract promises 0 ok / 1 no results / 2 bad usage / 3 store unavailable / 4 agent
/// not running.
@main
enum CapdMain {
    static func main() {
        do {
            var command = try Capd.parseAsRoot()
            try command.run()
        } catch let error as CLIError {
            error.terminate()
        } catch {
            guard Capd.exitCode(for: error) != .success else {
                Capd.exit(withError: error)
            }
            printToStderr(Capd.fullMessage(for: error))
            Darwin.exit(Capd.exitCode(for: error) == .validationFailure ? 2 : 1)
        }
    }
}
