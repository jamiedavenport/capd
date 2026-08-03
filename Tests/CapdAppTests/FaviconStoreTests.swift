import AppKit
import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("Favicon store")
struct FaviconStoreTests {
    @Test("A fetched icon lands in memory and on disk")
    func fetchCaches() async throws {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.icon(pngData: makePNG())))

        #expect(store.favicon(forHost: "www.Example.com") == nil)
        await store.awaitPendingFetches()

        #expect(store.favicon(forHost: "example.com") != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconURL(forHost: "example.com").path))

        // A fresh store — the next launch — reads the disk cache without fetching.
        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        #expect(relaunched.favicon(forHost: "example.com") == nil)
        await relaunched.awaitPendingFetches()
        #expect(relaunched.favicon(forHost: "example.com") != nil)
        #expect(counter.value == 0)
    }

    @Test("Dark artwork is flagged for a light backing; light artwork is not")
    func lightBackingVerdicts() async {
        let dark = FaviconStore(
            paths: temporaryPaths(),
            fetcher: stubFetcher(.icon(pngData: makePNG(fill: .black))))
        _ = dark.favicon(forHost: "example.com")
        await dark.awaitPendingFetches()
        #expect(dark.favicon(forHost: "example.com")?.needsLightBacking == true)

        let light = FaviconStore(
            paths: temporaryPaths(),
            fetcher: stubFetcher(.icon(pngData: makePNG(fill: .white))))
        _ = light.favicon(forHost: "example.com")
        await light.awaitPendingFetches()
        #expect(light.favicon(forHost: "example.com")?.needsLightBacking == false)
    }

    @Test("The verdict is recomputed from the bare PNG on a disk reload")
    func verdictSurvivesRelaunch() async {
        let paths = temporaryPaths()
        let store = FaviconStore(
            paths: paths, fetcher: stubFetcher(.icon(pngData: makePNG(fill: .black))))
        _ = store.favicon(forHost: "example.com")
        await store.awaitPendingFetches()

        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        _ = relaunched.favicon(forHost: "example.com")
        await relaunched.awaitPendingFetches()
        #expect(relaunched.favicon(forHost: "example.com")?.needsLightBacking == true)
        #expect(counter.value == 0)
    }

    @Test("A fetched SVG rasterizes into the same PNG cache")
    func svgRasterizes() async {
        let svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <rect width="24" height="24" fill="#3478f6"/>
            </svg>
            """.utf8)
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.svg(svg)))
        _ = store.favicon(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(store.favicon(forHost: "example.com") != nil)
        #expect(store.favicon(forHost: "example.com")?.needsLightBacking == false)
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconURL(forHost: "example.com").path))
    }

    @Test("A dark SVG is flagged after rasterizing")
    func darkSVGFlagged() async {
        let svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <rect width="24" height="24" fill="#000"/>
            </svg>
            """.utf8)
        let store = FaviconStore(paths: temporaryPaths(), fetcher: stubFetcher(.svg(svg)))
        _ = store.favicon(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(store.favicon(forHost: "example.com")?.needsLightBacking == true)
    }

    @Test("A confirmed miss writes a sentinel that suppresses refetching")
    func missSentinel() async {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.missing))
        _ = store.favicon(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconMissURL(forHost: "example.com").path))

        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        _ = relaunched.favicon(forHost: "example.com")
        await relaunched.awaitPendingFetches()
        #expect(relaunched.favicon(forHost: "example.com") == nil)
        #expect(counter.value == 0)
    }

    @Test("An expired sentinel is retried")
    func expiredSentinelRetries() async {
        let paths = temporaryPaths()
        let first = FaviconStore(paths: paths, fetcher: stubFetcher(.missing))
        _ = first.favicon(forHost: "example.com")
        await first.awaitPendingFetches()

        let counter = Counter()
        let later = FaviconStore(
            paths: paths,
            fetcher: countingFetcher(counter),
            now: { Date().addingTimeInterval(FaviconPolicy.missTTL + 1) })
        _ = later.favicon(forHost: "example.com")
        await later.awaitPendingFetches()
        #expect(counter.value == 1)
    }

    @Test("A transient failure leaves no sentinel, so the next launch retries")
    func transientFailureRetries() async {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.transientFailure))
        _ = store.favicon(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(
            !FileManager.default.fileExists(
                atPath: paths.faviconMissURL(forHost: "example.com").path))

        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        _ = relaunched.favicon(forHost: "example.com")
        await relaunched.awaitPendingFetches()
        #expect(counter.value == 1)
    }
}

private func temporaryPaths() -> StoragePaths {
    StoragePaths(
        root: FileManager.default.temporaryDirectory
            .appendingPathComponent("capd-favicon-tests-\(UUID().uuidString)", isDirectory: true))
}

private func stubFetcher(_ outcome: FaviconFetcher.Outcome) -> FaviconFetcher {
    let transport = FaviconTransportStub(outcome: outcome, counter: nil)
    return FaviconFetcher { try await transport.respond($0) }
}

private func countingFetcher(_ counter: Counter) -> FaviconFetcher {
    let transport = FaviconTransportStub(outcome: .icon(pngData: makePNG()), counter: counter)
    return FaviconFetcher { try await transport.respond($0) }
}

/// Answers `/favicon.ico` with whatever produces the wanted outcome, counting requests.
private struct FaviconTransportStub: Sendable {
    let outcome: FaviconFetcher.Outcome
    let counter: Counter?

    func respond(_ url: URL) async throws -> (Data, URLResponse) {
        counter?.increment()
        switch outcome {
        case .icon(let pngData) where url.path() == "/favicon.ico":
            return (pngData, response(url, status: 200))
        case .svg where url.path() == "/":
            let html = Data(#"<link rel="icon" href="/icon.svg" type="image/svg+xml">"#.utf8)
            return (html, response(url, status: 200))
        case .svg(let data) where url.path() == "/icon.svg":
            return (data, response(url, status: 200))
        case .transientFailure:
            throw URLError(.notConnectedToInternet)
        default:
            return (Data(), response(url, status: 404))
        }
    }

    private func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private func makePNG(fill: NSColor? = nil) -> Data {
    let size = 64
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)!
    if let fill, let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        fill.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    return bitmap.representation(using: .png, properties: [:])!
}
