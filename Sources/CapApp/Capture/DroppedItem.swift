import AppKit

/// One item of a drag, reduced to the representations cap can capture.
struct DroppedItem: Equatable, Sendable {
    var urlString: String? = nil
    var urlTitle: String? = nil
    var fileURL: URL? = nil
    var string: String? = nil
    var imagePNG: Data? = nil
}

extension DroppedItem {
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .URL, .fileURL, .png, .tiff, .string,
    ]

    private static let urlName = NSPasteboard.PasteboardType("public.url-name")

    /// Reads every item off the drag pasteboard, which is only guaranteed live while
    /// `performDragOperation` runs — hence a value copy rather than a lazy reader.
    static func items(from pasteboard: NSPasteboard) -> [DroppedItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { source in
            let item = DroppedItem(
                urlString: source.string(forType: .URL),
                urlTitle: source.string(forType: urlName),
                fileURL: source.string(forType: .fileURL)
                    .flatMap(URL.init(string:))?.standardizedFileURL,
                string: source.string(forType: .string),
                imagePNG: png(from: source))
            return item == DroppedItem() ? nil : item
        }
    }

    private static func png(from item: NSPasteboardItem) -> Data? {
        if let png = item.data(forType: .png) {
            return png
        }
        guard let tiff = item.data(forType: .tiff),
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
