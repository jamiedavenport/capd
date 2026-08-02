import Foundation
import Testing

/// The write path is only closed if it is closed to code outside the module, and
/// `@testable import` cannot show that. These typecheck a client-shaped source file against the
/// built `CapKit.swiftmodule` in a separate compiler invocation.
@Suite("Capture access control")
struct CaptureAccessControlTests {
    @Test("A client cannot reach the write path")
    func internalWritePathIsInvisibleToClients() throws {
        let result = try typecheckAsClient(
            """
            import CapKit
            import Foundation

            func probe(store: Store) throws {
                let capture = Capture(kind: .text, createdAt: Date())
                _ = try store.insertCapture(capture)
                _ = store.dbPool
                _ = try store.claimForEnrichment(id: 1, at: Date())
                _ = try store.applyExtraction(
                    id: 1, body: nil, bodyStatus: .failed, bodySource: .fetch,
                    enrichmentState: .failed, at: Date())
            }
            """)

        #expect(result.exitCode != 0)
        #expect(!result.diagnostics.contains("no such module"))
        #expect(result.diagnostics.contains("inaccessible due to 'internal' protection level"))
        #expect(result.diagnostics.contains("insertCapture"))
        #expect(result.diagnostics.contains("dbPool"))
        #expect(result.diagnostics.contains("claimForEnrichment"))
        #expect(result.diagnostics.contains("applyExtraction"))
        #expect(result.diagnostics.contains("no exact matches in call to initializer"))
    }

    @Test("A client can reach the capture surface")
    func publicCaptureSurfaceCompilesForClients() throws {
        let result = try typecheckAsClient(
            """
            import CapKit
            import Foundation

            func probe(store: Store) throws -> Capture {
                let service = CaptureService(store: store)
                return try service.ingest(CaptureRequest(url: "https://example.com/a"))
            }

            func enrich(store: Store) throws -> Capture {
                let service = EnrichmentService(store: store)
                _ = try service.claim(1)
                return try service.complete(
                    1, with: BodyExtractionResult(body: "words", status: .ok, source: .tab))
            }
            """)

        #expect(result.exitCode == 0)
        #expect(result.diagnostics.isEmpty)
    }
}

private struct TypecheckResult {
    let exitCode: Int32
    let diagnostics: String
}

private final class BundleToken {}

/// The fixture is written at runtime rather than checked in, so its deliberate errors never
/// join the test module or reach the linter.
private func typecheckAsClient(_ source: String) throws -> TypecheckResult {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-typecheck-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = directory.appendingPathComponent("Client.swift", isDirectory: false)
    try source.write(to: fixture, atomically: true, encoding: .utf8)

    let sdk = try run("/usr/bin/xcrun", ["--show-sdk-path", "--sdk", "macosx"]).output
        .trimmingCharacters(in: .whitespacesAndNewlines)
    try #require(!sdk.isEmpty, "xcrun could not locate the macOS SDK")

    var arguments = ["swiftc", "-typecheck", "-sdk", sdk, fixture.path]
    for path in try clientSearchPaths() {
        arguments.append(contentsOf: ["-I", path.path])
    }

    let result = try run("/usr/bin/xcrun", arguments)
    return TypecheckResult(exitCode: result.exitCode, diagnostics: result.output)
}

private func run(_ executable: String, _ arguments: [String]) throws -> (
    exitCode: Int32, output: String
) {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func clientSearchPaths() throws -> [URL] {
    let buildDirectory = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
    let modules = buildDirectory.appendingPathComponent("Modules", isDirectory: true)
    let holdingCapKit = [modules, buildDirectory].first { directory in
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("CapKit.swiftmodule").path)
    }
    let root = try #require(
        holdingCapKit, "no CapKit.swiftmodule near the test bundle at \(buildDirectory.path)")

    return [root] + checkoutModuleMapDirectories(near: buildDirectory)
}

/// Dependencies re-export C modules whose module maps SwiftPM leaves in the checkouts rather
/// than copying into the build directory. Only the ones under a package's `Sources` count:
/// GRDB also ships module maps for its Xcode framework targets, and those redeclare `GRDB`
/// itself as a framework module.
private func checkoutModuleMapDirectories(near buildDirectory: URL) -> [URL] {
    let manager = FileManager.default
    var candidate = buildDirectory

    while candidate.pathComponents.count > 1 {
        candidate = candidate.deletingLastPathComponent()
        let checkouts = candidate.appendingPathComponent("checkouts", isDirectory: true)
        guard
            let packages = try? manager.contentsOfDirectory(
                at: checkouts, includingPropertiesForKeys: nil)
        else { continue }

        return packages.flatMap { package in
            let sources = package.appendingPathComponent("Sources", isDirectory: true)
            let targets =
                (try? manager.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil))
                ?? []
            return targets.filter { target in
                manager.fileExists(atPath: target.appendingPathComponent("module.modulemap").path)
            }
        }
    }
    return []
}
