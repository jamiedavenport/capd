import Foundation

/// The rules for favicon fetching and caching, kept pure so every rule is testable offline.
public enum FaviconPolicy {
    public static let timeout: TimeInterval = 10
    public static let iconByteLimit = 2 * 1024 * 1024
    public static let htmlByteLimit = 1 * 1024 * 1024
    /// 2× the largest tile the app draws (22 pt), so favicons stay sharp on retina.
    public static let renderedPixelSize = 64
    /// An icon below this edge upscales visibly; the page HTML usually names a better one.
    public static let minimumCrispPixelSize = 32
    /// How long a confirmed miss stands before retrying; sites gain favicons rarely.
    public static let missTTL: TimeInterval = 7 * 24 * 3600
    /// Alpha-weighted mean luminance (gamma sRGB) below which artwork reads as dark.
    /// Kept under 0.45 so saturated brand blues stay on the normal chip.
    public static let darkArtworkLuminance = 0.40
    /// Alpha coverage at or above which an icon carries its own opaque background.
    public static let opaqueBackgroundCoverage = 0.90
    /// Border-ring luminance at or above which that opaque background counts as light.
    public static let lightBackgroundLuminance = 0.60
    /// Below this coverage the artwork is effectively empty; the verdict stays default.
    public static let minimumAnalyzableCoverage = 0.02

    /// One cache entry per site: lowercase, no `www.`, no port — the same worldview as
    /// the display URL in search rows. The result is a bare hostname, safe as a filename.
    public static func cacheKey(forHost host: String) -> String {
        var key = host.lowercased()
        if let colon = key.firstIndex(of: ":") {
            key = String(key[..<colon])
        }
        if key.hasPrefix("www.") {
            key = String(key.dropFirst(4))
        }
        return key
    }

    public static func isExpired(missRecordedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(missRecordedAt) >= missTTL
    }
}
