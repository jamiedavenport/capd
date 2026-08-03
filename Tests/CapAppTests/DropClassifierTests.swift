import AppKit
import CapKit
import Foundation
import Testing

@testable import CapApp
@testable import CapAppUI

@Suite("DropClassifier")
struct DropClassifierTests {
    @Test("A dragged web link becomes a link request carrying its page title")
    func webLink() throws {
        let requests = classify([
            DroppedItem(
                urlString: "https://example.com/a",
                urlTitle: "An example page",
                string: "https://example.com/a")
        ])

        let request = try #require(requests.first)
        #expect(request.url == "https://example.com/a")
        #expect(request.title == "An example page")
        #expect(request.text == nil)
    }

    @Test("A selection dragged alongside a link rides along as text")
    func linkWithDistinctSelection() throws {
        let requests = classify([
            DroppedItem(urlString: "https://example.com/a", string: "A quoted phrase")
        ])

        let request = try #require(requests.first)
        #expect(request.url == "https://example.com/a")
        #expect(request.text == "A quoted phrase")
    }

    @Test("A dropped image file becomes an image capture named after the file")
    func imageFile() throws {
        let file = try temporaryFile(named: "shot.png", contents: samplePNG())
        defer { try? FileManager.default.removeItem(at: file) }

        let request = try #require(classify([DroppedItem(fileURL: file)]).first)

        #expect(request.title == "shot.png")
        #expect(request.imageData?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(request.text == nil)
    }

    @Test("A non-image file is captured as its path")
    func plainFile() throws {
        let file = try temporaryFile(named: "notes.md", contents: Data("# hi".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let request = try #require(classify([DroppedItem(fileURL: file)]).first)

        #expect(request.text == file.path)
        #expect(request.title == "notes.md")
        #expect(request.imageData == nil)
    }

    @Test("An image file over the byte limit falls back to its path")
    func oversizedImageFile() throws {
        let file = try temporaryFile(named: "huge.png", contents: samplePNG())
        defer { try? FileManager.default.removeItem(at: file) }

        let requests = classify([DroppedItem(fileURL: file)], imageFileByteLimit: 4)

        #expect(requests.first?.imageData == nil)
        #expect(requests.first?.text == file.path)
    }

    @Test("A file URL riding in the URL slot is still treated as a file")
    func fileURLInURLSlot() throws {
        let file = try temporaryFile(named: "notes.md", contents: Data("# hi".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let request = try #require(
            classify([DroppedItem(urlString: file.absoluteString)]).first)

        #expect(request.url == nil)
        #expect(request.text == file.path)
    }

    @Test("Raw image data becomes an image capture")
    func rawImageData() throws {
        let request = try #require(classify([DroppedItem(imagePNG: samplePNG())]).first)

        #expect(request.imageData?.isEmpty == false)
        #expect(request.url == nil)
        #expect(request.text == nil)
    }

    @Test("A URL-shaped string becomes a link; prose stays text")
    func looseStrings() {
        let requests = classify([
            DroppedItem(string: "  https://example.com/dragged \n"),
            DroppedItem(string: "check https://example.com too"),
        ])

        #expect(requests.count == 2)
        #expect(requests.first?.url == "https://example.com/dragged")
        #expect(requests.last?.url == nil)
        #expect(requests.last?.text == "check https://example.com too")
    }

    @Test("A non-web URL falls through to the string it came with")
    func nonWebURL() throws {
        let request = try #require(
            classify([
                DroppedItem(urlString: "mailto:x@example.com", string: "mailto:x@example.com")
            ]).first)

        #expect(request.url == nil)
        #expect(request.text == "mailto:x@example.com")
    }

    @Test("Items classify in order, one request each")
    func multipleItems() {
        let requests = classify([
            DroppedItem(urlString: "https://example.com/a"),
            DroppedItem(string: "loose text"),
        ])

        #expect(requests.count == 2)
        #expect(requests.first?.url == "https://example.com/a")
        #expect(requests.last?.text == "loose text")
    }

    @Test("The drop's context reaches every request")
    func contextPropagates() throws {
        let request = try #require(classify([DroppedItem(string: "hello")]).first)

        #expect(request.sourceAppBundleID == "com.apple.finder")
        #expect(request.fetchBody == true)
        #expect(request.capturedAt == Date(timeIntervalSince1970: 0))
    }

    @Test("Nothing capturable classifies to nothing")
    func emptyItems() {
        #expect(classify([]).isEmpty)
        #expect(classify([DroppedItem(string: "   ")]).isEmpty)
    }
}

private func classify(
    _ items: [DroppedItem],
    imageFileByteLimit: Int = DropClassifier.imageFileByteLimit
) -> [CaptureRequest] {
    DropClassifier.requests(
        from: items,
        fetchBody: true,
        sourceAppBundleID: "com.apple.finder",
        now: Date(timeIntervalSince1970: 0),
        imageFileByteLimit: imageFileByteLimit)
}

private func temporaryFile(named name: String, contents: Data) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-drop-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(name)
    try contents.write(to: file)
    return file
}

private func samplePNG() -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return bitmap.representation(using: .png, properties: [:])!
}
