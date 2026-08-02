import AppKit
import Foundation
import GRDB
import SwiftSoup
import Testing

@testable import CapKit

/// One fixture in the committed corpus of real pages and screenshots.
struct CorpusEntry: Decodable, Sendable, CustomTestStringConvertible {
    enum Kind: String, Decodable, Sendable {
        case page
        case image
    }

    var slug: String
    var file: String
    var kind: Kind
    var url: String?
    var title: String
    var bodyContains: [String]?
    var ocrContains: [String]?
    var query: String
    /// The status extraction must land this page on — the golden expectation.
    var extraction: BodyStatus?

    var testDescription: String { slug }
}

enum GoldenCorpus {
    static let entries: [CorpusEntry] = {
        guard
            let manifest = Bundle.module.url(
                forResource: "manifest", withExtension: "json", subdirectory: "Fixtures/Corpus")
        else {
            fatalError("golden corpus manifest is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(
                [CorpusEntry].self, from: Data(contentsOf: manifest))
        } catch {
            fatalError("golden corpus manifest does not decode: \(error)")
        }
    }()

    static var pages: [CorpusEntry] { entries.filter { $0.kind == .page } }
    static var images: [CorpusEntry] { entries.filter { $0.kind == .image } }

    static func fileURL(of entry: CorpusEntry) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: entry.file, withExtension: nil, subdirectory: "Fixtures/Corpus"),
            "fixture file \(entry.file) is missing from the test bundle")
    }

    /// Parsed once per process: the ranking tests seed every page for every case, and
    /// re-parsing a megabyte of HTML per seed would dominate the suite's runtime.
    static let visibleTextBySlug: [String: String] = {
        var texts: [String: String] = [:]
        for entry in pages {
            guard
                let url = Bundle.module.url(
                    forResource: entry.file, withExtension: nil, subdirectory: "Fixtures/Corpus"),
                let html = try? String(contentsOf: url, encoding: .utf8),
                let text = try? SwiftSoup.parse(html).text()
            else { continue }
            texts[entry.slug] = text
        }
        return texts
    }()

    /// The salvage-tier extractor run over every page, once, exactly as the fetch path
    /// would run it on a snapshot Readability could not handle.
    static let extractionBySlug: [String: BodyExtractionResult] = {
        var results: [String: BodyExtractionResult] = [:]
        for entry in pages {
            guard
                let url = Bundle.module.url(
                    forResource: entry.file, withExtension: nil, subdirectory: "Fixtures/Corpus"),
                let html = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            let extracted = SoupExtractor.extract(
                html: html, url: entry.url.flatMap(URL.init(string:)))
            results[entry.slug] = BodyExtractionResult(classifying: extracted, source: .fetch)
        }
        return results
    }()
}

@Suite("Golden corpus")
struct GoldenCorpusTests {
    @Test("The corpus holds fifteen distinct fixtures")
    func corpusShape() throws {
        #expect(GoldenCorpus.entries.count == 15)
        #expect(GoldenCorpus.images.count == 2)
        #expect(Set(GoldenCorpus.entries.map(\.slug)).count == GoldenCorpus.entries.count)
        #expect(Set(GoldenCorpus.entries.map(\.query)).count == GoldenCorpus.entries.count)
        for entry in GoldenCorpus.entries {
            _ = try GoldenCorpus.fileURL(of: entry)
        }
    }

    @Test(
        "A page fixture's visible text carries its expected phrases", arguments: GoldenCorpus.pages)
    func pageFixtureIntegrity(entry: CorpusEntry) throws {
        let phrases = try #require(entry.bodyContains)
        #expect(!phrases.isEmpty)

        let text = try #require(GoldenCorpus.visibleTextBySlug[entry.slug])
        for phrase in phrases {
            #expect(text.contains(phrase), "\(entry.slug) lost the phrase \"\(phrase)\"")
        }
    }

    @Test("An image fixture decodes and names its expected reading", arguments: GoldenCorpus.images)
    func imageFixtureIntegrity(entry: CorpusEntry) throws {
        let data = try Data(contentsOf: GoldenCorpus.fileURL(of: entry))
        #expect(NSBitmapImageRep(data: data) != nil)
        let phrases = try #require(entry.ocrContains)
        #expect(!phrases.isEmpty)
    }

    /// The extraction golden expectations: each real page lands on its recorded status, and
    /// a kept body still holds the phrases a reader would search for.
    @Test("Extraction lands each page on its golden status", arguments: GoldenCorpus.pages)
    func extractionMatchesGoldenStatus(entry: CorpusEntry) throws {
        let expected = try #require(entry.extraction)
        let result = try #require(GoldenCorpus.extractionBySlug[entry.slug])

        #expect(result.status == expected, "\(entry.slug) classified \(result.status)")
        #expect(result.source == .fetch)

        if expected == .failed {
            #expect(result.body == nil)
        } else {
            let body = try #require(result.body)
            for phrase in try #require(entry.bodyContains) {
                #expect(body.contains(phrase), "extraction dropped \"\(phrase)\"")
            }
        }
    }

    /// The recall promise, run against real pages instead of toy strings: with the whole
    /// corpus indexed, each fixture's distinctive query must surface that fixture first.
    @Test("A distinctive query ranks its page first", arguments: GoldenCorpus.pages)
    func distinctiveQueryRanksItsPageFirst(entry: CorpusEntry) async throws {
        try await withCorpusStore { store in
            let hits = try SearchService(store: store).search(entry.query)

            let first = try #require(hits.first, "\(entry.query) found nothing")
            #expect(first.capture.url == entry.url)
        }
    }

    @Test("OCR makes a screenshot findable among the pages", arguments: GoldenCorpus.images)
    func screenshotIsFindableAfterEnrichment(entry: CorpusEntry) async throws {
        try await withCorpusStore { store in
            let outcome = try CaptureService(store: store).ingest(
                CaptureRequest(
                    imageData: try Data(contentsOf: GoldenCorpus.fileURL(of: entry)),
                    title: entry.title))
            let id = try #require(outcome.capture.id)

            let enrichment = EnrichmentService(store: store, steps: [OCRStep()])
            let processed = try #require(try await enrichment.process(captureID: id))
            #expect(processed.enrichmentState == .ok)

            let ocrText = try #require(processed.ocrText).lowercased()
            for phrase in try #require(entry.ocrContains) {
                #expect(ocrText.contains(phrase), "\(entry.slug) OCR lost \"\(phrase)\"")
            }

            let hits = try SearchService(store: store).search(entry.query)
            #expect(try #require(hits.first).capture.id == id)
        }
    }
}

/// A store seeded with every page fixture, titled and bodied as a capture of that page.
private func withCorpusStore(_ body: (Store) async throws -> Void) async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(makeCorpusStore(root: root))
}

private func temporaryRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-corpus-tests-\(UUID().uuidString)", isDirectory: true)
}

private func makeCorpusStore(root: URL) throws -> Store {
    let store = try Store(paths: StoragePaths(root: root))
    let base = Date(timeIntervalSince1970: 1_770_000_000)

    try store.dbPool.write { db in
        for (index, entry) in GoldenCorpus.pages.enumerated() {
            let url = entry.url.flatMap(URL.init(string:))
            let extraction = GoldenCorpus.extractionBySlug[entry.slug]
            var capture = Capture(
                kind: .link,
                url: entry.url,
                host: url?.host()?.lowercased(),
                title: entry.title,
                body: extraction?.body,
                enrichmentState: .ok,
                bodyStatus: extraction?.status ?? .none,
                bodySource: extraction?.source,
                createdAt: base.addingTimeInterval(Double(index))
            )
            try capture.insert(db)
        }
    }
    return store
}
