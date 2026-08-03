import AppKit

/// A restorable copy of a pasteboard's entire contents.
///
/// The synthetic-copy capture fallback overwrites the user's clipboard and must put back
/// exactly what it found, so the snapshot is taken first — and when a faithful restore is
/// impossible, ``capture(_:byteLimit:)`` returns nil and the caller skips the fallback
/// rather than destroy what it cannot recreate.
public struct PasteboardSnapshot: Sendable {
    /// Past this, holding a copy in memory is a worse trade than skipping the fallback.
    public static let defaultByteLimit = 10 * 1024 * 1024

    /// Per item, each declared type's bytes in declaration order, which readers treat
    /// as richest-first.
    private let items: [[(type: String, data: Data)]]

    public var itemCount: Int { items.count }

    /// Nil when the pasteboard cannot be restored faithfully: an item promises a file only
    /// its source app can deliver, a declared type yields no data, or the total size passes
    /// `byteLimit`. Reading resolves lazily-provided data, so a provider that does deliver
    /// is captured as plain bytes.
    public static func capture(
        _ pasteboard: NSPasteboard,
        byteLimit: Int = PasteboardSnapshot.defaultByteLimit
    ) -> PasteboardSnapshot? {
        var captured: [[(type: String, data: Data)]] = []
        var totalBytes = 0

        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [(type: String, data: Data)] = []
            for type in item.types {
                guard !Self.promiseTypes.contains(type.rawValue) else { return nil }
                guard let data = item.data(forType: type) else { return nil }
                totalBytes += data.count
                guard totalBytes <= byteLimit else { return nil }
                entry.append((type.rawValue, data))
            }
            captured.append(entry)
        }
        return PasteboardSnapshot(items: captured)
    }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(
            items.map { entry in
                let item = NSPasteboardItem()
                for (type, data) in entry {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                return item
            })
    }

    /// A promised file exists only inside the source app until a drop target asks for it;
    /// no snapshot can restore one.
    private static let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
}
