import CapdKit
import Foundation

/// Ingests link captures against an existing store, so a test can drive real cross-process
/// WAL contention: this binary plays the CLI adding captures while the test process enriches.
///
/// Usage: `CapdTestHost <store-root> <count> <label>`

let arguments = CommandLine.arguments
guard arguments.count == 4, let count = Int(arguments[2]), count > 0 else {
    FileHandle.standardError.write(Data("usage: CapdTestHost <store-root> <count> <label>\n".utf8))
    exit(2)
}

do {
    let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let service = CaptureService(store: try Store(paths: StoragePaths(root: root)))
    for index in 0..<count {
        _ = try service.ingest(
            CaptureRequest(
                url: "https://contention.test/\(arguments[3])/\(index)",
                title: "Contention \(arguments[3]) \(index)"))
    }
} catch {
    FileHandle.standardError.write(Data("CapdTestHost: \(error)\n".utf8))
    exit(1)
}
