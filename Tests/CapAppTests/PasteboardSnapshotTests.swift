import AppKit
import Testing

@testable import CapApp

@Suite("PasteboardSnapshot")
struct PasteboardSnapshotTests {
    @Test("The clipboard survives being overwritten and restored")
    func roundTrip() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let original = NSPasteboardItem()
        original.setString("hello", forType: .string)
        original.setData(Data([0x01, 0x02]), forType: .init("dev.jxd.cap.test-type"))
        pasteboard.writeObjects([original])

        let snapshot = try PasteboardSnapshot.snapshot(of: pasteboard).get()
        pasteboard.clearContents()
        pasteboard.setString("overwritten by a synthetic copy", forType: .string)
        snapshot.restore(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(
            pasteboard.data(forType: .init("dev.jxd.cap.test-type")) == Data([0x01, 0x02]))
    }

    @Test("Promised content refuses the snapshot before anything is read")
    func promisedContentRefused() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(Data(), forType: .init("com.apple.pasteboard.promised-file-url"))
        pasteboard.writeObjects([item])

        #expect(
            PasteboardSnapshot.snapshot(of: pasteboard)
                == .failure(.promisedContent))
    }

    @Test("Content over the size cap refuses the snapshot")
    func oversizedContentRefused() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(Data(count: 1024), forType: .string)

        #expect(
            PasteboardSnapshot.snapshot(of: pasteboard, byteLimit: 512)
                == .failure(.tooLarge))
    }

    @Test("An empty clipboard restores to empty")
    func emptyClipboardRoundTrips() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        let snapshot = try PasteboardSnapshot.snapshot(of: pasteboard).get()
        pasteboard.setString("junk", forType: .string)
        snapshot.restore(to: pasteboard)

        #expect(pasteboard.pasteboardItems?.isEmpty == true)
    }
}
