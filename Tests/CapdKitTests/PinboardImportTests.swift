import Foundation
import GRDB
import Testing

@testable import CapdKit

@Suite("Pinboard import")
struct PinboardImportTests {
    @Test("A post maps onto the capture fields")
    func postMapsToCapture() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let summary = try importer(store).run(
                data: Data(
                    """
                    [{"href":"https:\\/\\/example.com\\/article",
                      "description":"An Article",
                      "extended":"Worth keeping",
                      "meta":"c2fa","hash":"8a01",
                      "time":"2019-03-04T18:20:23Z",
                      "shared":"yes","toread":"no",
                      "tags":"swift macOS Dev-Tools"}]
                    """.utf8))

            #expect(summary == summarized(imported: 1))
            let capture = try #require(try onlyCapture(store))
            #expect(capture.kind == .link)
            #expect(capture.url == "https://example.com/article")
            #expect(capture.title == "An Article")
            #expect(capture.note == "Worth keeping")
            #expect(capture.tagList == ["swift", "macos", "dev-tools"])
            #expect(capture.tagsVersion == Capture.pinnedTagsVersion)
            #expect(capture.createdAt == Date(timeIntervalSince1970: 1_551_723_623))
            #expect(capture.lastSeenAt == capture.createdAt)
            #expect(capture.enrichmentState == .ok)
        }
    }

    @Test("An unread bookmark keeps its read-later status as a toread tag")
    func toreadBecomesTag() {
        let request = PinboardImporter.request(
            for: PinboardPost(href: "https://example.com", tags: "later", toread: "yes"))
        #expect(request.tags == ["later", "toread"])
    }

    @Test("Blank title, note, and tags stay empty, leaving the row for auto-tagging")
    func blankFieldsStayEmpty() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            _ = try importer(store).run(
                data: Data(
                    """
                    [{"href":"https://example.com","description":"","extended":"","tags":""}]
                    """.utf8))

            let capture = try #require(try onlyCapture(store))
            #expect(capture.title == nil)
            #expect(capture.note == nil)
            #expect(capture.tags == nil)
            #expect(capture.tagsVersion == 0)
        }
    }

    @Test("An unparseable time falls back to the import date")
    func badTimeFallsBack() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = PinboardImporter.request(
            for: PinboardPost(href: "https://example.com", time: "not-a-date"), now: now)
        #expect(request.capturedAt == now)
    }

    @Test("A bad row is reported and the rest import")
    func badRowDoesNotAbortTheRun() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let summary = try importer(store).run(
                data: Data(
                    """
                    [{"href":"ftp:\\/\\/example.com\\/file"},
                     {"href":"https:\\/\\/example.com\\/good"}]
                    """.utf8))

            #expect(summary.imported == 1)
            #expect(summary.merged == 0)
            #expect(summary.failures.map(\.href) == ["ftp://example.com/file"])
            #expect(try captureCount(store) == 1)
        }
    }

    @Test("Anything but an array of bookmarks is rejected whole")
    func nonExportIsRejected() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            #expect(throws: PinboardImportError.notAPinboardExport) {
                try importer(store).run(data: Data("{\"posts\": []}".utf8))
            }
            #expect(throws: PinboardImportError.notAPinboardExport) {
                try importer(store).run(data: Data("not json".utf8))
            }
        }
    }

    @Test("Re-running the same export merges every row instead of duplicating")
    func reimportIsIdempotent() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let export = Data(
                """
                [{"href":"https:\\/\\/example.com\\/a","tags":"swift"},
                 {"href":"https:\\/\\/example.com\\/b"}]
                """.utf8)

            let first = try importer(store).run(data: export)
            let second = try importer(store).run(data: export)

            #expect(first == summarized(imported: 2))
            #expect(second == summarized(merged: 2))
            #expect(try captureCount(store) == 2)
        }
    }

    @Test("Imported tags fill an untagged row but never replace the agent's")
    func mergeAdoptsTagsOnlyIntoGaps() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let bare = try service.ingest(CaptureRequest(url: "https://example.com/a")).capture
            let tagged = try service.ingest(CaptureRequest(url: "https://example.com/b")).capture
            try store.completeTagging(
                id: try #require(tagged.id), tags: ["agents"],
                taxonomy: Taxonomy(tags: ["agents"], updatedAt: Date()))

            _ = try importer(store).run(
                data: Data(
                    """
                    [{"href":"https:\\/\\/example.com\\/a","tags":"pinboard"},
                     {"href":"https:\\/\\/example.com\\/b","tags":"pinboard"}]
                    """.utf8))

            let mergedBare = try #require(try fetchCapture(store, id: bare.id))
            #expect(mergedBare.tagList == ["pinboard"])
            #expect(mergedBare.tagsVersion == Capture.pinnedTagsVersion)

            let mergedTagged = try #require(try fetchCapture(store, id: tagged.id))
            #expect(mergedTagged.tagList == ["agents"])
        }
    }

    @Test("Pinned tags are invisible to the tagging pass")
    func pinnedRowsAreNotRetagged() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            _ = try CaptureService(store: store).ingest(
                CaptureRequest(url: "https://example.com/a", tags: ["pinboard"], fetchBody: false))

            #expect(try store.untaggedCaptures(limit: 10).isEmpty)
        }
    }

    @Test("Consolidation neither counts nor rewrites pinned tags")
    func consolidationLeavesPinnedTagsAlone() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            let service = CaptureService(store: store)

            let pinned = try service.ingest(
                CaptureRequest(
                    url: "https://example.com/a", tags: ["vintage", "pinboard"], fetchBody: false)
            ).capture
            let agented = try service.ingest(
                CaptureRequest(url: "https://example.com/b", fetchBody: false)
            ).capture
            var taxonomy = Taxonomy(tags: ["old"], updatedAt: Date())
            try store.completeTagging(
                id: try #require(agented.id), tags: ["old"], taxonomy: taxonomy)

            #expect(try store.tagUsage(includePinned: false).map(\.tag) == ["old"])
            #expect(
                try store.tagUsage().map(\.tag).sorted() == ["old", "pinboard", "vintage"])

            taxonomy.version += 1
            taxonomy.tags = ["new"]
            try store.applyTaxonomyRevision(mapping: ["old": "new"], taxonomy: taxonomy)

            let untouched = try #require(try fetchCapture(store, id: pinned.id))
            #expect(untouched.tagList == ["vintage", "pinboard"])
            #expect(untouched.tagsVersion == Capture.pinnedTagsVersion)
            #expect(try #require(try fetchCapture(store, id: agented.id)).tagList == ["new"])
        }
    }

    private func importer(_ store: Store) -> PinboardImporter {
        PinboardImporter(captures: CaptureService(store: store))
    }

    private func summarized(imported: Int = 0, merged: Int = 0) -> PinboardImportSummary {
        var summary = PinboardImportSummary()
        summary.imported = imported
        summary.merged = merged
        return summary
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capd-pinboard-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}

private func captureCount(_ store: Store) throws -> Int {
    try store.reader.read { db in try Capture.fetchCount(db) }
}

private func onlyCapture(_ store: Store) throws -> Capture? {
    try store.reader.read { db in try Capture.fetchOne(db) }
}

private func fetchCapture(_ store: Store, id: Int64?) throws -> Capture? {
    guard let id else { return nil }
    return try store.reader.read { db in try Capture.fetchOne(db, key: id) }
}
