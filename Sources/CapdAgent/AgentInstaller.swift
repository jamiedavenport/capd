import CapdKit
import Foundation

enum AgentInstallerError: Error {
    case missingTemplate
    case missingExecutable
    case launchctlFailed(command: String, status: Int32)
}

/// Writes the LaunchAgent plist pointing launchd at this executable and bootstraps it,
/// so captures from any source enrich with no UI running.
enum AgentInstaller {
    static let label = AgentAdmin.label

    /// Replaced in the template rather than generated, so the shipped plist stays
    /// readable and diffable.
    static let executableToken = "CAPD_AGENT_EXECUTABLE"

    static var installedPlistURL: URL {
        AgentAdmin.installedPlistURL
    }

    static func renderedPlist(executablePath: String) throws -> String {
        guard let templateURL = Bundle.module.url(forResource: label, withExtension: "plist")
        else {
            throw AgentInstallerError.missingTemplate
        }
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        return template.replacingOccurrences(of: executableToken, with: xmlEscaped(executablePath))
    }

    /// A no-op when the installed plist already points at this executable and launchd
    /// has it loaded, so callers may run it on every launch.
    static func install(executableURL: URL? = Bundle.main.executableURL) throws {
        guard let executableURL else {
            throw AgentInstallerError.missingExecutable
        }
        let rendered = try renderedPlist(executablePath: executableURL.path)
        let destination = installedPlistURL
        if (try? String(contentsOf: destination, encoding: .utf8)) == rendered,
            AgentAdmin.isLoaded()
        {
            return
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rendered.write(to: destination, atomically: true, encoding: .utf8)

        // Bootout first: bootstrap refuses a label that is already loaded, and a
        // reinstall must pick up a moved executable.
        AgentAdmin.bootout()
        let status = AgentAdmin.bootstrap(plistURL: destination)
        guard status == 0 else {
            throw AgentInstallerError.launchctlFailed(command: "bootstrap", status: status)
        }
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
