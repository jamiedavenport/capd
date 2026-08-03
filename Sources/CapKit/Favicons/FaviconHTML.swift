import Foundation
import SwiftSoup

/// One icon a page declares in its `<head>`.
public struct FaviconCandidate: Sendable, Equatable {
    public var url: URL?
    public var inlineData: Data?
    public var isSVG: Bool
    public var isAppleTouch: Bool
    public var declaredSize: Int?
}

/// Finds the icons a page declares, pure so every shape of `<link>` is testable offline.
public enum FaviconHTML {
    public static func candidates(in html: String, pageURL: URL) -> [FaviconCandidate] {
        guard let document = try? SwiftSoup.parse(html, pageURL.absoluteString),
            let links = try? document.select("link[href]")
        else {
            return []
        }
        var results: [FaviconCandidate] = []
        for link in links.array() {
            let rel = ((try? link.attr("rel")) ?? "").lowercased()
            let tokens = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            let isAppleTouch =
                tokens.contains("apple-touch-icon")
                || tokens.contains("apple-touch-icon-precomposed")
            // `mask-icon` is a single token, so it never matches: those are monochrome
            // templates, the wrong artwork for a tile.
            guard tokens.contains("icon") || isAppleTouch else { continue }
            guard let href = try? link.attr("href"), !href.isEmpty else { continue }
            let type = ((try? link.attr("type")) ?? "").lowercased()
            let declared = maxEdge(inSizes: (try? link.attr("sizes")) ?? "")

            if let (data, svgFromMeta) = inlineData(fromDataURL: href) {
                results.append(
                    FaviconCandidate(
                        url: nil,
                        inlineData: data,
                        isSVG: svgFromMeta || type.contains("svg"),
                        isAppleTouch: isAppleTouch,
                        declaredSize: declared))
                continue
            }
            guard let resolved = URL(string: href, relativeTo: pageURL)?.absoluteURL else {
                continue
            }
            results.append(
                FaviconCandidate(
                    url: resolved,
                    inlineData: nil,
                    isSVG: type.contains("svg")
                        || resolved.path(percentEncoded: false).lowercased().hasSuffix(".svg"),
                    isAppleTouch: isAppleTouch,
                    declaredSize: declared))
        }
        return results
    }

    /// The candidate worth one network request: closest declared size at or above the
    /// rendered size wins; an undeclared size outranks a known-small one because it could
    /// be anything; raster beats SVG at equal rank because it decodes without AppKit.
    public static func best(_ candidates: [FaviconCandidate]) -> FaviconCandidate? {
        candidates.min { score($0) < score($1) }
    }

    private static func score(_ candidate: FaviconCandidate) -> (Int, Int, Int) {
        let svgPenalty = candidate.isSVG ? 1 : 0
        // Apple-touch icons are conventionally 180px even when undeclared.
        let size = candidate.declaredSize ?? (candidate.isAppleTouch ? 180 : nil)
        guard let size else { return (1, 0, svgPenalty) }
        if size >= FaviconPolicy.renderedPixelSize {
            return (0, size - FaviconPolicy.renderedPixelSize, svgPenalty)
        }
        return (2, FaviconPolicy.renderedPixelSize - size, svgPenalty)
    }

    /// `sizes="32x32 64x64"` → 64; `any` and junk → nil.
    private static func maxEdge(inSizes sizes: String) -> Int? {
        sizes.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .compactMap { entry -> Int? in
                let edges = entry.split(separator: "x").compactMap { Int($0) }
                return edges.count == 2 ? edges.max() : nil
            }
            .max()
    }

    private static func inlineData(fromDataURL href: String) -> (Data, isSVG: Bool)? {
        guard href.lowercased().hasPrefix("data:"), let comma = href.firstIndex(of: ",")
        else {
            return nil
        }
        let meta = href[href.index(href.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(href[href.index(after: comma)...])
        let isSVG = meta.contains("image/svg")
        if meta.contains("base64") {
            guard let data = Data(base64Encoded: payload) else { return nil }
            return (data, isSVG)
        }
        guard let decoded = payload.removingPercentEncoding else { return nil }
        return (Data(decoded.utf8), isSVG)
    }
}
