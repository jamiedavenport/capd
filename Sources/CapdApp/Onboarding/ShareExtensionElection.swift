import CapdAppUI
import CapdKit
import Foundation

/// Reads and sets the share-sheet election for Capd's share extension. The toggle in
/// System Settings → General → Login Items & Extensions → Sharing writes the same
/// pluginkit election, so `use` is exactly "enable Capd in the share sheet".
enum ShareExtensionElection {
    static let extensionIdentifier = "\(CapdKit.bundleIdentifier).share"

    static func status() -> ShareExtensionStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", extensionIdentifier]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unregistered
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // One line per match, election first: "+" elected, "-" diselected, and a
        // space when the user has never touched it.
        guard let line = String(data: output, encoding: .utf8), !line.isEmpty else {
            return .unregistered
        }
        switch line.first {
        case "+": return .enabled
        case "-": return .disabled
        default: return .defaulted
        }
    }

    static func enable() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-e", "use", "-i", extensionIdentifier]
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()
    }
}
