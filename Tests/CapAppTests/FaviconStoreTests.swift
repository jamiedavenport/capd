import AppKit
import Foundation
import Testing

@testable import CapApp
@testable import CapAppUI
@testable import CapKit

@MainActor
@Suite("Favicon store")
struct FaviconStoreTests {
    @Test("A fetched icon lands in memory and on disk")
    func fetchCaches() async throws {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.icon(pngData: makePNG())))

        #expect(store.image(forHost: "www.Example.com") == nil)
        await store.awaitPendingFetches()

        #expect(store.image(forHost: "example.com") != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconURL(forHost: "example.com").path))

        // A fresh store — the next launch — reads the disk cache without fetching.
        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        #expect(relaunched.image(forHost: "example.com") == nil)
        await relaunched.awaitPendingFetches()
        #expect(relaunched.image(forHost: "example.com") != nil)
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
        _ = store.image(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(store.image(forHost: "example.com") != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconURL(forHost: "example.com").path))
    }

    @Test("A confirmed miss writes a sentinel that suppresses refetching")
    func missSentinel() async {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.missing))
        _ = store.image(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(
            FileManager.default.fileExists(
                atPath: paths.faviconMissURL(forHost: "example.com").path))

        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        _ = relaunched.image(forHost: "example.com")
        await relaunched.awaitPendingFetches()
        #expect(relaunched.image(forHost: "example.com") == nil)
        #expect(counter.value == 0)
    }

    @Test("An expired sentinel is retried")
    func expiredSentinelRetries() async {
        let paths = temporaryPaths()
        let first = FaviconStore(paths: paths, fetcher: stubFetcher(.missing))
        _ = first.image(forHost: "example.com")
        await first.awaitPendingFetches()

        let counter = Counter()
        let later = FaviconStore(
            paths: paths,
            fetcher: countingFetcher(counter),
            now: { Date().addingTimeInterval(FaviconPolicy.missTTL + 1) })
        _ = later.image(forHost: "example.com")
        await later.awaitPendingFetches()
        #expect(counter.value == 1)
    }

    @Test("A transient failure leaves no sentinel, so the next launch retries")
    func transientFailureRetries() async {
        let paths = temporaryPaths()
        let store = FaviconStore(paths: paths, fetcher: stubFetcher(.transientFailure))
        _ = store.image(forHost: "example.com")
        await store.awaitPendingFetches()
        #expect(
            !FileManager.default.fileExists(
                atPath: paths.faviconMissURL(forHost: "example.com").path))

        let counter = Counter()
        let relaunched = FaviconStore(paths: paths, fetcher: countingFetcher(counter))
        _ = relaunched.image(forHost: "example.com")
        await relaunched.awaitPendingFetches()
        #expect(counter.value == 1)
    }
}

private func temporaryPaths() -> StoragePaths {
    StoragePaths(
        root: FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-favicon-tests-\(UUID().uuidString)", isDirectory: true))
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

private func makePNG() -> Data {
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
    return bitmap.representation(using: .png, properties: [:])!
}
