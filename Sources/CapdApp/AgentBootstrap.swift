import CapdKit
import Foundation

/// Keeps the enrichment agent installed. The agent does its own installing so the
/// launchd plist always names the binary launchd will run; the app only has to find its
/// sibling executable. Installation is a no-op when the agent is current and loaded, so
/// this runs on every launch and doubles as repair.
enum AgentBootstrap {
    static let agentLabel = "\(CapdKit.bundleIdentifier).agent"

    static func installAgent() {
        guard let executable = Bundle.main.executableURL else { return }
        let agent = executable.deletingLastPathComponent()
            .appendingPathComponent("capd-agent", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: agent.path) else { return }

        let process = Process()
        process.executableURL = agent
        process.arguments = ["install"]
        try? process.run()
    }

    /// Mirrors the agent's own `isLoaded()` check; the app can't import an executable
    /// target, so it asks launchd directly.
    static func isAgentLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(agentLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
