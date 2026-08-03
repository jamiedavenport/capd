import AppKit
import CapKit
import Foundation

/// Turns the items of one drop into capture requests, one per item, with the hotkey
/// path's precedence: a web link beats a file, a file beats raw image data, and loose
/// text splits on `LinkDetection`.
enum DropClassifier {
    /// Above this, a dropped image file is captured as a path rather than decoded:
    /// re-encoding a huge original to PNG could dwarf the store.
    static let imageFileByteLimit = 20 * 1024 * 1024

    static func requests(
        from items: [DroppedItem],
        fetchBody: Bool,
        sourceAppBundleID: String?,
        now: Date,
        imageFileByteLimit: Int = Self.imageFileByteLimit
    ) -> [CaptureRequest] {
        items.compactMap { item in
            request(
                from: item,
                fetchBody: fetchBody,
                sourceAppBundleID: sourceAppBundleID,
                now: now,
                imageFileByteLimit: imageFileByteLimit)
        }
    }

    private static func request(
        from item: DroppedItem,
        fetchBody: Bool,
        sourceAppBundleID: String?,
        now: Date,
        imageFileByteLimit: Int
    ) -> CaptureRequest? {
        if let url = webURL(item.urlString) {
            let selection = trimmed(item.string)
            return CaptureRequest(
                url: url,
                // Browsers mirror the dragged link into the string slot; only a
                // genuine selection rides along as text.
                text: selection == url ? nil : selection,
                title: trimmed(item.urlTitle),
                sourceAppBundleID: sourceAppBundleID,
                fetchBody: fetchBody,
                capturedAt: now)
        }

        if let fileURL = item.fileURL ?? fileURL(from: item.urlString) {
            if let png = decodedPNG(at: fileURL, byteLimit: imageFileByteLimit) {
                return CaptureRequest(
                    imageData: png,
                    title: fileURL.lastPathComponent,
                    sourceAppBundleID: sourceAppBundleID,
                    fetchBody: fetchBody,
                    capturedAt: now)
            }
            // Local links have no kind of their own; the path as searchable text is
            // the closest thing to a bookmark for a file.
            return CaptureRequest(
                text: fileURL.path,
                title: fileURL.lastPathComponent,
                sourceAppBundleID: sourceAppBundleID,
                fetchBody: fetchBody,
                capturedAt: now)
        }

        if let png = item.imagePNG, !png.isEmpty {
            return CaptureRequest(
                imageData: png,
                sourceAppBundleID: sourceAppBundleID,
                fetchBody: fetchBody,
                capturedAt: now)
        }

        if let string = trimmed(item.string) {
            if LinkDetection.looksLikeURL(string) {
                return CaptureRequest(
                    url: string,
                    sourceAppBundleID: sourceAppBundleID,
                    fetchBody: fetchBody,
                    capturedAt: now)
            }
            return CaptureRequest(
                text: string,
                sourceAppBundleID: sourceAppBundleID,
                fetchBody: fetchBody,
                capturedAt: now)
        }

        return nil
    }

    private static func webURL(_ candidate: String?) -> String? {
        guard let candidate = trimmed(candidate),
            let scheme = URL(string: candidate)?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return candidate
    }

    /// Finder occasionally rides a file URL in the `public.url` slot with no
    /// `public.file-url` next to it.
    private static func fileURL(from urlString: String?) -> URL? {
        guard let candidate = trimmed(urlString),
            let url = URL(string: candidate), url.isFileURL
        else { return nil }
        return url.standardizedFileURL
    }

    private static func decodedPNG(at url: URL, byteLimit: Int) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= byteLimit,
            let data = try? Data(contentsOf: url),
            let bitmap = NSBitmapImageRep(data: data)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
