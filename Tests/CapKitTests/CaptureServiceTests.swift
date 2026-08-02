import CryptoKit
import Foundation
import GRDB
import Testing

@testable import CapKit

@Suite("CaptureService")
struct CaptureServiceTests {
    @Test("A request carrying all three payloads is captured as a link")
    func urlOutranksTextAndImage() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(
                    url: "https://example.com/a",
                    text: "A quoted phrase",
                    imageData: samplePNG)
            ).capture

            #expect(capture.kind == .link)
            #expect(capture.url == "https://example.com/a")
            #expect(capture.selection == "A quoted phrase")
            #expect(capture.assetPath == nil)
            #expect(try writtenAssets(paths).isEmpty)
        }
    }

    @Test("Text outranks an image")
    func textOutranksImage() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(text: "A quoted phrase", imageData: samplePNG)
            ).capture

            #expect(capture.kind == .text)
            #expect(capture.selection == "A quoted phrase")
            #expect(capture.url == nil)
            #expect(capture.assetPath == nil)
            #expect(try writtenAssets(paths).isEmpty)
        }
    }

    @Test("An image lands on disk under its own digest")
    func imageCaptureWritesContentAddressedAsset() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(imageData: samplePNG)
            ).capture

            let digest = hexDigest(of: samplePNG)
            let assetPath = try #require(capture.assetPath)
            #expect(assetPath == "\(digest.prefix(2))/\(digest).png")

            let onDisk = paths.assetURL(forRelativePath: assetPath)
            #expect(try Data(contentsOf: onDisk) == samplePNG)
        }
    }

    @Test("A request with no payload is refused")
    func emptyRequestIsRefused() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            #expect(throws: CaptureError.emptyRequest) {
                try service.ingest(CaptureRequest())
            }
            #expect(throws: CaptureError.emptyRequest) {
                try service.ingest(
                    CaptureRequest(url: "   ", text: "\n\t ", imageData: Data()))
            }
            #expect(try captureCount(store) == 0)
        }
    }

    @Test(
        "A link that is not http or https is refused",
        arguments: [
            "ftp://example.com/a",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "https://",
            "not a url",
        ])
    func nonHTTPURLsAreRefused(candidate: String) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            #expect(throws: CaptureError.invalidURL(candidate)) {
                try service.ingest(CaptureRequest(url: candidate, text: "A quoted phrase"))
            }
            #expect(try captureCount(store) == 0)
        }
    }

    @Test(
        "State at birth follows the kind and the fetch flag",
        arguments: [
            BirthState(
                request: CaptureRequest(url: "https://example.com/a", text: "A quoted phrase"),
                kind: .link,
                enrichmentState: .pending,
                url: "https://example.com/a",
                host: "example.com",
                selection: "A quoted phrase",
                hasAsset: false
            ),
            BirthState(
                request: CaptureRequest(
                    url: "https://example.com/a", text: "A quoted phrase", fetchBody: false),
                kind: .link,
                enrichmentState: .ok,
                url: "https://example.com/a",
                host: "example.com",
                selection: "A quoted phrase",
                hasAsset: false
            ),
            BirthState(
                request: CaptureRequest(url: "https://example.com/a"),
                kind: .link,
                enrichmentState: .pending,
                url: "https://example.com/a",
                host: "example.com",
                selection: nil,
                hasAsset: false
            ),
            BirthState(
                request: CaptureRequest(text: "A standalone thought", fetchBody: true),
                kind: .text,
                enrichmentState: .ok,
                url: nil,
                host: nil,
                selection: "A standalone thought",
                hasAsset: false
            ),
            BirthState(
                request: CaptureRequest(imageData: samplePNG, fetchBody: true),
                kind: .image,
                enrichmentState: .pending,
                url: nil,
                host: nil,
                selection: nil,
                hasAsset: true
            ),
        ])
    func stateInitFollowsKindAndFetchFlag(expected: BirthState) throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(expected.request).capture

            #expect(capture.kind == expected.kind)
            #expect(capture.enrichmentState == expected.enrichmentState)
            #expect(capture.bodyStatus == BodyStatus.none)
            #expect(capture.url == expected.url)
            #expect(capture.host == expected.host)
            #expect(capture.selection == expected.selection)
            #expect((capture.assetPath != nil) == expected.hasAsset)
            #expect(capture.body == nil)
            #expect(capture.bodySource == nil)
            #expect(capture.attemptCount == 0)
            #expect(capture.seenCount == 1)
        }
    }

    @Test("A link's host is stored lowercased")
    func hostIsPopulatedAndLowercased() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(url: "  HTTPS://EXAMPLE.COM/Path  ")
            ).capture

            #expect(capture.host == "example.com")
        }
    }

    @Test("The content hash is a SHA-256 of what identifies the capture")
    func contentHashIsSHA256OfCanonicalInput() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let link = try service.ingest(
                CaptureRequest(url: " HTTPS://Example.com:443/a?utm_source=tw#frag ")
            ).capture
            let text = try service.ingest(CaptureRequest(text: " A standalone thought ")).capture
            let image = try service.ingest(CaptureRequest(imageData: samplePNG)).capture

            #expect(link.contentHash == hexDigest(of: Data("https://example.com/a".utf8)))
            #expect(text.contentHash == hexDigest(of: Data("A standalone thought".utf8)))
            #expect(image.contentHash == hexDigest(of: samplePNG))
        }
    }

    @Test("Ingest returns exactly what was persisted")
    func ingestReturnsThePersistedCapture() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(
                    url: "https://example.com/a", title: "Persisted", capturedAt: wholeSecond))

            let capture = outcome.capture
            #expect(outcome == .captured(capture))
            #expect(capture.id != nil)

            let stored = try store.reader.read { db in
                try Capture.fetchOne(db)
            }
            #expect(stored == capture)
        }
    }

    @Test("An ingested capture is findable in the full-text index")
    func ingestPopulatesTheFullTextIndex() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let capture = try CaptureService(store: store).ingest(
                CaptureRequest(
                    url: "https://example.com/a",
                    text: "Marmot husbandry",
                    title: "Ptarmigan strategies")
            ).capture
            let id = try #require(capture.id)

            #expect(try matchingRowIDs(store, "ptarmigan") == [id])
            #expect(try matchingRowIDs(store, "marmot") == [id])
        }
    }

    @Test("A guard that refuses stops the capture before anything is written")
    func aRefusingGuardWritesNothing() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store, guards: [RefusingGuard()])

            #expect(throws: GuardRefusal.self) {
                try service.ingest(CaptureRequest(imageData: samplePNG))
            }
            #expect(throws: GuardRefusal.self) {
                try service.ingest(CaptureRequest())
            }
            #expect(try captureCount(store) == 0)
            #expect(try writtenAssets(paths).isEmpty)
        }
    }

    @Test("An active secure-input probe stops the capture before anything is written")
    func activeSecureInputProbeWritesNothing() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(
                store: store, guards: [SecureInputGuard(probes: [StubProbe(active: true)])])

            #expect(throws: CaptureError.secureInputActive) {
                try service.ingest(CaptureRequest(url: "https://example.com/a"))
            }
            #expect(throws: CaptureError.secureInputActive) {
                try service.ingest(CaptureRequest(imageData: samplePNG))
            }
            #expect(try captureCount(store) == 0)
            #expect(try writtenAssets(paths).isEmpty)
        }
    }

    @Test("Inactive secure-input probes let the capture through")
    func inactiveSecureInputProbesAllowCapture() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(
                store: store,
                guards: [
                    SecureInputGuard(probes: [StubProbe(active: false), StubProbe(active: false)])
                ])

            let capture = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture

            #expect(capture.kind == .link)
            #expect(try captureCount(store) == 1)
        }
    }

    @Test("The first refusing probe short-circuits later probes")
    func refusingProbeShortCircuitsLaterProbes() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(
                store: store,
                guards: [
                    SecureInputGuard(probes: [StubProbe(active: true), UnconsultedProbe()])
                ])

            #expect(throws: CaptureError.secureInputActive) {
                try service.ingest(CaptureRequest(url: "https://example.com/a"))
            }
        }
    }

    @Test("The secure-input refusal carries its user-facing message")
    func secureInputRefusalCarriesItsMessage() {
        #expect(
            CaptureError.secureInputActive.errorDescription
                == "Capture blocked — secure input active.")
    }

    @Test("Everything the caller supplied reaches the row")
    func requestMetadataFlowsThrough() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(
                    url: "https://example.com/a",
                    title: "A title",
                    note: "A note",
                    sourceAppBundleID: "com.apple.Safari",
                    capturedAt: wholeSecond))

            let stored = try #require(
                try store.reader.read { db in
                    try Capture.fetchOne(db)
                })

            #expect(stored.title == "A title")
            #expect(stored.note == "A note")
            #expect(stored.sourceAppBundleID == "com.apple.Safari")
            #expect(stored.createdAt == wholeSecond)
            #expect(stored.updatedAt == wholeSecond)
            #expect(stored.lastSeenAt == wholeSecond)
            #expect(outcome == .captured(stored))
        }
    }
}

struct BirthState: Sendable {
    let request: CaptureRequest
    let kind: CaptureKind
    let enrichmentState: EnrichmentState
    let url: String?
    let host: String?
    let selection: String?
    let hasAsset: Bool
}

private struct GuardRefusal: Error, Equatable {}

private struct RefusingGuard: CaptureGuard {
    func check(_ request: CaptureRequest) throws {
        throw GuardRefusal()
    }
}

private struct StubProbe: SecureInputProbe {
    let active: Bool

    func isSecureInputActive() -> Bool {
        active
    }
}

private struct UnconsultedProbe: SecureInputProbe {
    func isSecureInputActive() -> Bool {
        Issue.record("a probe was consulted after an earlier probe already refused")
        return false
    }
}

private let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

/// Comparing a returned capture against its stored row needs a date that survives the round
/// trip, and GRDB stores dates as strings that stop at the millisecond.
private let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-capture-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func hexDigest(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func captureCount(_ store: Store) throws -> Int {
    try store.reader.read { db in
        try Capture.fetchCount(db)
    }
}

private func writtenAssets(_ paths: StoragePaths) throws -> [URL] {
    let enumerated = FileManager.default.enumerator(
        at: paths.assetsDirectory, includingPropertiesForKeys: [.isRegularFileKey])
    guard let enumerated else { return [] }
    return enumerated.compactMap { $0 as? URL }.filter { url in
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

private func matchingRowIDs(_ store: Store, _ query: String) throws -> [Int64] {
    try store.reader.read { db in
        try Int64.fetchAll(
            db,
            sql: """
                SELECT rowid FROM \(Schema.capturesFTS)
                WHERE \(Schema.capturesFTS) MATCH ?
                """,
            arguments: [query])
    }
}
