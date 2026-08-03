import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finds one favicon for a host: the well-known ico, then the page's declared icons,
/// then a few well-known alternates. Redirects are followed even cross-host — icon CDNs
/// are the norm, and the page-fetch navigation lock exists to keep body extraction
/// honest, not to constrain artwork. Bytes are validated by decoding them instead.
public struct FaviconFetcher: Sendable {
    public enum Outcome: Sendable, Equatable {
        case icon(pngData: Data)
        /// SVG can't be decoded without AppKit; the app layer rasterizes it.
        case svg(Data)
        case missing
        case transientFailure
    }

    /// Injectable so tests never touch the network.
    public var transport: @Sendable (URL) async throws -> (Data, URLResponse)

    public init(transport: @escaping @Sendable (URL) async throws -> (Data, URLResponse)) {
        self.transport = transport
    }

    public static let live = FaviconFetcher { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = FaviconPolicy.timeout
        return try await URLSession(configuration: .ephemeral).data(for: request)
    }

    public func fetch(host: String) async -> Outcome {
        let key = FaviconPolicy.cacheKey(forHost: host)
        guard let icoURL = URL(string: "https://\(key)/favicon.ico"),
            FetchPolicy.isFetchable(icoURL)
        else {
            return .missing
        }

        var sawTransientFailure = false
        var smallIcon: Data?

        switch await download(icoURL, limit: FaviconPolicy.iconByteLimit) {
        case .success(let data):
            if let (png, pixelSize) = Self.normalize(data) {
                if pixelSize >= FaviconPolicy.minimumCrispPixelSize {
                    return .icon(pngData: png)
                }
                smallIcon = png
            }
        case .notFound:
            break
        case .transient:
            sawTransientFailure = true
        }

        if let pageURL = URL(string: "https://\(key)/") {
            switch await download(pageURL, limit: FaviconPolicy.htmlByteLimit, prefixing: true) {
            case .success(let data):
                let html = String(decoding: data, as: UTF8.self)
                let candidate = FaviconHTML.best(
                    FaviconHTML.candidates(in: html, pageURL: pageURL))
                switch await resolve(candidate) {
                case .some(let outcome):
                    return outcome
                case .none:
                    break
                case .transient:
                    sawTransientFailure = true
                }
            case .notFound:
                break
            case .transient:
                sawTransientFailure = true
            }
        }

        for path in ["/apple-touch-icon.png", "/favicon.png", "/favicon.svg"] {
            guard let url = URL(string: "https://\(key)\(path)") else { continue }
            switch await download(url, limit: FaviconPolicy.iconByteLimit) {
            case .success(let data):
                if path.hasSuffix(".svg") {
                    if Self.looksLikeSVG(data) {
                        return .svg(data)
                    }
                } else if let (png, _) = Self.normalize(data) {
                    return .icon(pngData: png)
                }
            case .notFound:
                break
            case .transient:
                sawTransientFailure = true
            }
        }

        if let smallIcon {
            return .icon(pngData: smallIcon)
        }
        return sawTransientFailure ? .transientFailure : .missing
    }

    private enum Resolution {
        case some(Outcome)
        case none
        case transient
    }

    private func resolve(_ candidate: FaviconCandidate?) async -> Resolution {
        guard let candidate else { return .none }
        if let inline = candidate.inlineData {
            if candidate.isSVG {
                return .some(.svg(inline))
            }
            if let (png, _) = Self.normalize(inline) {
                return .some(.icon(pngData: png))
            }
            return .none
        }
        guard let url = candidate.url, FetchPolicy.isFetchable(url) else { return .none }
        switch await download(url, limit: FaviconPolicy.iconByteLimit) {
        case .success(let data):
            if candidate.isSVG {
                return Self.looksLikeSVG(data) ? .some(.svg(data)) : .none
            }
            if let (png, _) = Self.normalize(data) {
                return .some(.icon(pngData: png))
            }
            return .none
        case .notFound:
            return .none
        case .transient:
            return .transient
        }
    }

    private enum DownloadResult {
        case success(Data)
        case notFound
        case transient
    }

    private func download(
        _ url: URL, limit: Int, prefixing: Bool = false
    ) async -> DownloadResult {
        do {
            let (data, response) = try await transport(url)
            guard let http = response as? HTTPURLResponse else { return .transient }
            guard http.statusCode == 200 else {
                return (500...599).contains(http.statusCode) ? .transient : .notFound
            }
            if data.count > limit {
                // The interesting part of a page — its <head> — sits at the front.
                return prefixing ? .success(data.prefix(limit)) : .notFound
            }
            return .success(data)
        } catch {
            return .transient
        }
    }

    /// Largest rep in, one PNG at display size out. ImageIO rather than NSImage keeps
    /// AppKit out of CapdKit; the multi-resolution answer for .ico is picking the rep.
    static func normalize(_ data: Data) -> (pngData: Data, pixelSize: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var bestIndex = 0
        var bestEdge = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                    as? [CFString: Any]
            else { continue }
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            let edge = max(width, height)
            if edge > bestEdge {
                bestEdge = edge
                bestIndex = index
            }
        }
        guard bestEdge > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(bestEdge, FaviconPolicy.renderedPixelSize),
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, bestIndex, options as CFDictionary)
        else {
            return nil
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, bestEdge)
    }

    static func looksLikeSVG(_ data: Data) -> Bool {
        String(decoding: data.prefix(1024), as: UTF8.self).lowercased().contains("<svg")
    }
}
