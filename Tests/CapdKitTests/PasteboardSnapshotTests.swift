import AppKit
import Testing

@testable import CapdKit

@Suite("Pasteboard snapshot")
struct PasteboardSnapshotTests {
    private let customType = NSPasteboard.PasteboardType("dev.jxd.capd.tests.blob")

    @Test("Contents round-trip through snapshot and restore")
    func roundTrip() throws {
        try withPrivatePasteboard { pasteboard in
            let rich = NSPasteboardItem()
            rich.setString("hello clipboard", forType: .string)
            rich.setData(Data([0x01, 0x02, 0x03]), forType: customType)
            let plain = NSPasteboardItem()
            plain.setString("https://example.com/x", forType: .string)
            pasteboard.writeObjects([rich, plain])

            let snapshot = try #require(PasteboardSnapshot.capture(pasteboard))
            #expect(snapshot.itemCount == 2)

            pasteboard.clearContents()
            pasteboard.setString("overwritten by a synthetic copy", forType: .string)

            snapshot.restore(to: pasteboard)

            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.count == 2)
            #expect(items[0].string(forType: .string) == "hello clipboard")
            #expect(items[0].data(forType: customType) == Data([0x01, 0x02, 0x03]))
            #expect(items[1].string(forType: .string) == "https://example.com/x")
        }
    }

    @Test("An empty pasteboard snapshots, and restoring empties again")
    func emptyRoundTrip() throws {
        try withPrivatePasteboard { pasteboard in
            let snapshot = try #require(PasteboardSnapshot.capture(pasteboard))
            #expect(snapshot.itemCount == 0)

            pasteboard.setString("junk a capture left behind", forType: .string)
            snapshot.restore(to: pasteboard)

            #expect(pasteboard.pasteboardItems?.isEmpty == true)
        }
    }

    @Test("A file promise makes the pasteboard unrestorable")
    func filePromiseRefusesTheSnapshot() throws {
        try withPrivatePasteboard { pasteboard in
            let promiseType = try #require(NSFilePromiseReceiver.readableDraggedTypes.first)
            let item = NSPasteboardItem()
            item.setString("preview text", forType: .string)
            item.setData(Data(), forType: NSPasteboard.PasteboardType(promiseType))
            pasteboard.writeObjects([item])

            #expect(PasteboardSnapshot.capture(pasteboard) == nil)
            #expect(pasteboard.pasteboardItems?.count == 1)
        }
    }

    @Test("Contents past the byte limit make the pasteboard unrestorable")
    func oversizeRefusesTheSnapshot() throws {
        try withPrivatePasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(Data(count: 4096), forType: customType)
            pasteboard.writeObjects([item])

            #expect(PasteboardSnapshot.capture(pasteboard, byteLimit: 1024) == nil)
            #expect(PasteboardSnapshot.capture(pasteboard, byteLimit: 4096) != nil)
        }
    }

    @Test("A lazy type that never delivers makes the pasteboard unrestorable")
    func undeliveredLazyTypeRefusesTheSnapshot() throws {
        try withPrivatePasteboard { pasteboard in
            let provider = NeverDeliveringProvider()
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [customType])
            pasteboard.writeObjects([item])

            #expect(PasteboardSnapshot.capture(pasteboard) == nil)
        }
    }
}

private final class NeverDeliveringProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        // Deliberately writes nothing, modelling a source app that has quit.
    }
}

private func withPrivatePasteboard(_ body: (NSPasteboard) throws -> Void) throws {
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("dev.jxd.capd.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    try body(pasteboard)
}
