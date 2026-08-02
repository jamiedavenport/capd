import ArgumentParser
import CapKit

/// The `cap` command-line interface.
@main
struct Cap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cap",
        abstract: "Capture and recall anything you have seen.",
        version: CapKit.version
    )

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}
