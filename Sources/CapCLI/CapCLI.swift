import ArgumentParser
import CapKit

/// The `cap` command-line interface.
///
/// Subcommands (add / search / list / rm / export / refetch / status / doctor), the
/// `--json` and `--format tsv` output contract, stdin piping, and exit codes
/// 0/1/2/3/4 are defined in the CLI contract ticket (C3/T8). This scaffold
/// establishes only the binary and its version.
@main
struct Cap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cap",
        abstract: "Capture and recall anything you have seen.",
        version: CapKit.version
    )

    func run() throws {
        print("cap \(CapKit.version) — no commands yet. See `cap --help`.")
    }
}
