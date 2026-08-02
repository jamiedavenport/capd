import Foundation
import Testing

private final class BinaryLocator {}

/// The `cap` product lands in the same build directory as this test bundle.
private let capBinary = Bundle(for: BinaryLocator.self).bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("cap", isDirectory: false)

struct CLIRun {
    let status: Int32
    let stdout: String
    let stderr: String
}

@discardableResult
func cap(_ arguments: [String], stdin: String? = nil, root: URL) throws -> CLIRun {
    let process = Process()
    process.executableURL = capBinary
    process.arguments = arguments

    var environment = ProcessInfo.processInfo.environment
    environment["CAP_DIR"] = root.path
    process.environment = environment

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    if let stdin {
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
    } else {
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    // Drain before waiting, or a full pipe buffer deadlocks the child.
    let outData = try output.fileHandleForReading.readToEnd() ?? Data()
    let errData = try errors.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()

    return CLIRun(
        status: process.terminationStatus,
        stdout: String(decoding: outData, as: UTF8.self),
        stderr: String(decoding: errData, as: UTF8.self))
}

func withScratchRoot(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-cli-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

func jsonArray(_ text: String) throws -> [[String: Any]] {
    let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return try #require(parsed as? [[String: Any]])
}

func jsonObject(_ text: String) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return try #require(parsed as? [String: Any])
}
