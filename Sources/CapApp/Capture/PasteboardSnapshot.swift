import AppKit

/// A byte-for-byte copy of the pasteboard, taken before the synthetic ⌘C so the user's
/// clipboard survives the capture.
///
/// Refuses rather than guesses: content that cannot be read back losslessly is never
/// touched, and the caller skips the fallback instead.
struct PasteboardSnapshot: Equatable {
    enum Failure: Error, Equatable {
        /// Promised data lives in the source app until pasted; reading it triggers side
        /// effects and writing it back is impossible.
        case promisedContent
        case tooLarge
    }

    static let byteLimit = 10 * 1024 * 1024

    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func snapshot(
        of pasteboard: NSPasteboard, byteLimit: Int = Self.byteLimit
    ) -> Result<PasteboardSnapshot, Failure> {
        let pasteboardItems = pasteboard.pasteboardItems ?? []

        let holdsPromise = pasteboardItems.contains { item in
            item.types.contains { $0.rawValue.localizedCaseInsensitiveContains("promise") }
        }
        guard !holdsPromise else { return .failure(.promisedContent) }

        var total = 0
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboardItems {
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                total += data.count
                guard total <= byteLimit else { return .failure(.tooLarge) }
                payload[type] = data
            }
            items.append(payload)
        }
        return .success(PasteboardSnapshot(items: items))
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
