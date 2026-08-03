import ArgumentParser
import CapKit
import Darwin
import Foundation

/// The `cap` command-line interface.
struct Cap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cap",
        abstract: "Capture and recall anything you have seen.",
        version: CapKit.version,
        subcommands: [
            Add.self, Search.self, List.self, Rm.self, Export.self, Refetch.self,
            Status.self, Doctor.self, Mcp.self,
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
enum CapMain {
    static func main() async {
        do {
            var command = try Cap.parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as CLIError {
            error.terminate()
        } catch {
            guard Cap.exitCode(for: error) != .success else {
                Cap.exit(withError: error)
            }
            printToStderr(Cap.fullMessage(for: error))
            Darwin.exit(Cap.exitCode(for: error) == .validationFailure ? 2 : 1)
        }
    }
}
