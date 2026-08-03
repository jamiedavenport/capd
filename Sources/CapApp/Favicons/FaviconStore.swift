import AppKit
import CapKit
import Observation
import SwiftUI

/// Per-host favicon cache: memory in front of `favicons/` on disk, filled on the first
/// sight of a host. Views read synchronously and fall back to a symbol tile; the fetch
/// completing mutates observed state, which repaints whichever rows asked.
@MainActor
@Observable
final class FaviconStore {
    private let paths: StoragePaths
    private let fetcher: FaviconFetcher
    private let now: () -> Date
    private var images: [String: NSImage] = [:]
    /// Hosts with a settled answer this session — including misses and transient
    /// failures, so an offline launch doesn't retry on every keystroke.
    @ObservationIgnored private var resolved: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(
        paths: StoragePaths,
        fetcher: FaviconFetcher = .live,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fetcher = fetcher
        self.now = now
    }

    /// Deliberately does no I/O: it runs inside view bodies, and mutating observed
    /// state there is not allowed. The disk check rides the same background task as
    /// the network fetch and lands a frame later.
    func image(forHost host: String) -> NSImage? {
        let key = FaviconPolicy.cacheKey(forHost: host)
        if let image = images[key] {
            return image
        }
        if !resolved.contains(key), tasks[key] == nil {
            tasks[key] = Task { await resolve(key) }
        }
        return nil
    }

    /// Lets tests run the fetches spawned by `image(forHost:)` to completion.
    func awaitPendingFetches() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func resolve(_ key: String) async {
        defer { tasks[key] = nil }

        if let data = try? Data(contentsOf: paths.faviconURL(forHost: key)),
            let image = NSImage(data: data)
        {
            images[key] = image
            resolved.insert(key)
            return
        }
        if let recordedAt = missDate(forKey: key),
            !FaviconPolicy.isExpired(missRecordedAt: recordedAt, now: now())
        {
            resolved.insert(key)
            return
        }

        switch await fetcher.fetch(host: key) {
        case .icon(let pngData):
            store(pngData, forKey: key)
        case .svg(let data):
            if let pngData = Self.rasterizeSVG(data) {
                store(pngData, forKey: key)
            } else {
                recordMiss(forKey: key)
            }
        case .missing:
            recordMiss(forKey: key)
        case .transientFailure:
            resolved.insert(key)
        }
    }

    private func store(_ pngData: Data, forKey key: String) {
        resolved.insert(key)
        guard let image = NSImage(data: pngData) else {
            recordMiss(forKey: key)
            return
        }
        try? FileManager.default.createDirectory(
            at: paths.faviconsDirectory, withIntermediateDirectories: true)
        try? pngData.write(to: paths.faviconURL(forHost: key))
        try? FileManager.default.removeItem(at: paths.faviconMissURL(forHost: key))
        images[key] = image
    }

    private func recordMiss(forKey key: String) {
        resolved.insert(key)
        try? FileManager.default.createDirectory(
            at: paths.faviconsDirectory, withIntermediateDirectories: true)
        try? Data().write(to: paths.faviconMissURL(forHost: key))
    }

    private func missDate(forKey key: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: paths.faviconMissURL(forHost: key).path)
        return attributes?[.modificationDate] as? Date
    }

    /// SVG never touches CapKit's ImageIO path; CoreSVG via NSImage is best-effort and
    /// an undrawable file simply counts as a miss.
    private static func rasterizeSVG(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), image.isValid else { return nil }
        let size = FaviconPolicy.renderedPixelSize
        guard
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
                bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension EnvironmentValues {
    /// nil — the default — degrades every favicon tile to its symbol fallback, so
    /// previews and tests need no setup.
    @Entry var faviconStore: FaviconStore?
}
