import ApplicationServices
import ArgumentParser
import CapKit
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check and repair the store and the enrichment agent.",
        discussion: """
            Runs a database integrity check, rebuilds the search index, sweeps orphaned \
            asset files, and verifies the launchd agent, reinstalling it when needed. \
            Exits 1 when a problem remains that it could not repair.
            """)

    @Flag(help: "Remove the launchd agent and its plist, then stop.")
    var uninstallAgent = false

    @Flag(help: "Leave the launchd agent alone; check only the store.")
    var skipAgent = false

    func run() throws {
        if uninstallAgent {
            print(try AgentAdmin.uninstall() ? "Agent: uninstalled" : "Agent: not installed")
            return
        }

        let store = try openStore()
        var healthy = true

        let integrity = try store.checkIntegrity()
        if integrity == ["ok"] {
            print("Database: ok")
        } else {
            healthy = false
            print("Database: integrity check FAILED")
            for finding in integrity {
                print("  \(finding)")
            }
        }

        let indexed = try store.rebuildSearchIndex()
        print("Search index: rebuilt (\(indexed) capture\(indexed == 1 ? "" : "s"))")

        let sweep = try store.sweepOrphanAssets()
        if sweep.removedPaths.isEmpty {
            print("Assets: no orphans")
        } else {
            let count = sweep.removedPaths.count
            print("Assets: removed \(count) orphaned file\(count == 1 ? "" : "s")")
        }
        if !sweep.missingCaptureIDs.isEmpty {
            healthy = false
            let plural = sweep.missingCaptureIDs.count == 1 ? "" : "s"
            let ids = sweep.missingCaptureIDs.map { "#\($0)" }.joined(separator: ", ")
            print("Assets: missing for capture\(plural) \(ids)")
        }

        if !skipAgent {
            healthy = repairAgent() && healthy
        }

        // Informational, and about this process: the Accessibility grant is keyed to the
        // code signature, so the app's own grant can differ.
        print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted") for this process")

        guard healthy else {
            throw CLIError(message: "", code: 1)
        }
    }

    /// The reinstall shells out to `cap-agent install` rather than writing the plist
    /// here, so the plist always names the binary launchd will run.
    private func repairAgent() -> Bool {
        if AgentAdmin.isInstalled() && AgentAdmin.isLoaded() {
            print("Agent: loaded")
            return true
        }

        let agent = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("cap-agent", isDirectory: false)
        guard let agent, FileManager.default.isExecutableFile(atPath: agent.path) else {
            print("Agent: not loaded, and no cap-agent binary found next to cap to reinstall")
            return false
        }

        let process = Process()
        process.executableURL = agent
        process.arguments = ["install"]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do {
            try process.run()
        } catch {
            print("Agent: reinstall failed — \(describe(error))")
            return false
        }
        let detail = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, AgentAdmin.isLoaded() else {
            let reason = String(decoding: detail, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("Agent: reinstall failed" + (reason.isEmpty ? "" : " — \(reason)"))
            return false
        }
        print("Agent: reinstalled")
        return true
    }
}
