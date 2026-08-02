import Darwin
import Foundation

/// launchd and liveness facts about the enrichment agent, shared by the agent (which
/// installs itself) and the CLI (`cap status` reports, `cap doctor` repairs).
public enum AgentAdmin {
    public static let label = "\(CapKit.bundleIdentifier).agent"

    public static var installedPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
    }

    public static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedPlistURL.path)
    }

    public static func isLoaded() -> Bool {
        launchctl(["print", "gui/\(getuid())/\(label)"]) == 0
    }

    /// Whether a live agent holds this store's lock. The probe tries the lock without
    /// blocking; contention is the signal, so it works for manually run agents too.
    public static func isRunning(paths: StoragePaths) -> Bool {
        let descriptor = open(paths.agentLockURL.path, O_RDWR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(descriptor, LOCK_UN)
        return false
    }

    public static func bootstrap(plistURL: URL) -> Int32 {
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    @discardableResult
    public static func bootout() -> Int32 {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
    }

    /// Unloads the agent and deletes its plist; false means nothing was installed.
    @discardableResult
    public static func uninstall() throws -> Bool {
        bootout()
        guard isInstalled() else { return false }
        try FileManager.default.removeItem(at: installedPlistURL)
        return true
    }

    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
