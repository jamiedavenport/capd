import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CapdKit

@Suite("FaviconFetcher")
struct FaviconFetcherTests {
    @Test("A crisp well-known ico wins without touching the page")
    func icoFirst() async throws {
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(makePNG(edge: 64))
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        let png = try #require(pngData(from: outcome))
        #expect(decodedEdge(of: png) == 64)
    }

    @Test("The largest rep of a multi-resolution ico is the one normalized")
    func multiRepICO() async throws {
        let ico = makeICO(entries: [makePNG(edge: 16), makePNG(edge: 48)])
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(ico)
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        let png = try #require(pngData(from: outcome))
        #expect(decodedEdge(of: png) == 48)
    }

    @Test("Oversized art is thumbnailed down to the rendered size")
    func downscaling() async throws {
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(makePNG(edge: 512))
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        let png = try #require(pngData(from: outcome))
        #expect(decodedEdge(of: png) == FaviconPolicy.renderedPixelSize)
    }

    @Test("A missing ico falls back to the page's declared icon")
    func htmlFallback() async throws {
        let fetcher = stubFetcher([
            "/": .ok(Data(#"<link rel="icon" href="/art/icon.png">"#.utf8)),
            "/art/icon.png": .ok(makePNG(edge: 64)),
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        #expect(pngData(from: outcome) != nil)
    }

    @Test("A declared SVG passes through undecoded")
    func svgPassthrough() async throws {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
        let fetcher = stubFetcher([
            "/": .ok(Data(#"<link rel="icon" href="/icon.svg" type="image/svg+xml">"#.utf8)),
            "/icon.svg": .ok(svg),
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        #expect(outcome == .svg(svg))
    }

    @Test("With no ico and a bare page, the well-known alternates are probed")
    func lastResortProbes() async throws {
        let fetcher = stubFetcher([
            "/": .ok(Data("<html><body>no icons here</body></html>".utf8)),
            "/apple-touch-icon.png": .ok(makePNG(edge: 180)),
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        let png = try #require(pngData(from: outcome))
        #expect(decodedEdge(of: png) == FaviconPolicy.renderedPixelSize)
    }

    @Test("A tiny ico is kept when nothing better exists")
    func smallIcoKept() async throws {
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(makePNG(edge: 16))
        ])
        let outcome = await fetcher.fetch(host: "example.com")
        let png = try #require(pngData(from: outcome))
        #expect(decodedEdge(of: png) == 16)
    }

    @Test("An HTML error page served as the ico fails decode and falls through")
    func htmlAsIco() async {
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(Data("<html>404-ish</html>".utf8))
        ])
        #expect(await fetcher.fetch(host: "example.com") == .missing)
    }

    @Test("404 everywhere is a definitive miss")
    func allNotFound() async {
        #expect(await stubFetcher([:]).fetch(host: "example.com") == .missing)
    }

    @Test("Network failure is transient, not a miss")
    func networkFailure() async {
        let fetcher = FaviconFetcher { _ in throw URLError(.notConnectedToInternet) }
        #expect(await fetcher.fetch(host: "example.com") == .transientFailure)
    }

    @Test("An icon over the byte limit is rejected")
    func byteLimit() async {
        let fetcher = stubFetcher([
            "/favicon.ico": .ok(Data(count: FaviconPolicy.iconByteLimit + 1))
        ])
        #expect(await fetcher.fetch(host: "example.com") == .missing)
    }
}

private enum StubResponse {
    case ok(Data)
    case status(Int)
}

/// 404 for any path not routed.
private func stubFetcher(_ routes: [String: StubResponse]) -> FaviconFetcher {
    FaviconFetcher { url in
        let response = routes[url.path()] ?? .status(404)
        switch response {
        case .ok(let data):
            return (data, httpResponse(url, status: 200))
        case .status(let code):
            return (Data(), httpResponse(url, status: code))
        }
    }
}

private func httpResponse(_ url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func pngData(from outcome: FaviconFetcher.Outcome) -> Data? {
    if case .icon(let pngData) = outcome {
        return pngData
    }
    return nil
}

private func decodedEdge(of data: Data) -> Int? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        return nil
    }
    return max(width, height)
}

private func makePNG(edge: Int) -> Data {
    let context = CGContext(
        data: nil,
        width: edge,
        height: edge,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
    let image = context.makeImage()!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

/// A Vista-style ico whose entries are PNG blobs, which is what modern favicons are.
private func makeICO(entries: [Data]) -> Data {
    var out = Data()
    func le16(_ value: Int) {
        out.append(UInt8(value & 0xff))
        out.append(UInt8((value >> 8) & 0xff))
    }
    func le32(_ value: Int) {
        for shift in stride(from: 0, through: 24, by: 8) {
            out.append(UInt8((value >> shift) & 0xff))
        }
    }
    le16(0)
    le16(1)
    le16(entries.count)
    var offset = 6 + 16 * entries.count
    for entry in entries {
        let edge = decodedEdge(of: entry) ?? 0
        out.append(UInt8(edge >= 256 ? 0 : edge))
        out.append(UInt8(edge >= 256 ? 0 : edge))
        out.append(0)
        out.append(0)
        le16(1)
        le16(32)
        le32(entry.count)
        le32(offset)
        offset += entry.count
    }
    for entry in entries {
        out.append(entry)
    }
    return out
}
