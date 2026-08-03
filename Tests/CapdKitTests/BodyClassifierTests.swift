import Foundation
import Testing

@testable import CapdKit

@Suite("BodyClassifier")
struct BodyClassifierTests {
    @Test("Nothing extracted is a failure")
    func nothingExtractedFails() {
        #expect(BodyClassifier.classify(nil) == .failed)
        #expect(BodyClassifier.classify(ExtractedBody(text: "")) == .failed)
        #expect(BodyClassifier.classify(ExtractedBody(text: " \n\t ")) == .failed)
    }

    @Test(
        "Word count alone separates thin from ok",
        arguments: [
            (BodyClassifier.thinWordCount - 1, BodyStatus.thin),
            (BodyClassifier.thinWordCount, BodyStatus.ok),
            (BodyClassifier.wallSuspectWordCount, BodyStatus.ok),
        ])
    func wordCountBoundary(count: Int, expected: BodyStatus) {
        #expect(BodyClassifier.classify(ExtractedBody(text: words(count))) == expected)
    }

    @Test(
        "A password field marks a short page as a wall, not a long one",
        arguments: [
            (BodyClassifier.wallSuspectWordCount - 1, BodyStatus.thin),
            (BodyClassifier.wallSuspectWordCount, BodyStatus.ok),
        ])
    func passwordFieldBoundary(count: Int, expected: BodyStatus) {
        let extracted = ExtractedBody(text: words(count), hasPasswordField: true)
        #expect(BodyClassifier.classify(extracted) == expected)
    }

    @Test("Two distinct login signals on a short page mean a wall")
    func twoSignalsOnShortPageAreThin() {
        let text = words(489) + " Sign in here or confess you are Already a Subscriber"
        #expect(BodyClassifier.classify(ExtractedBody(text: text)) == .thin)
    }

    @Test("One signal, or a repeated one, is page furniture")
    func fewerThanTwoDistinctSignalsAreOK() {
        let one = words(497) + " sign in"
        let repeated = words(495) + " sign in sign in"
        #expect(BodyClassifier.classify(ExtractedBody(text: one)) == .ok)
        #expect(BodyClassifier.classify(ExtractedBody(text: repeated)) == .ok)
    }

    @Test("Login signals stop counting once the page is long enough")
    func signalsIgnoredOnLongPages() {
        let text =
            words(BodyClassifier.wallSuspectWordCount)
            + " sign in and remember you are already a subscriber"
        #expect(BodyClassifier.classify(ExtractedBody(text: text)) == .ok)
    }

    @Test("Classification decides what a result stores")
    func resultStoresBodyUnlessFailed() {
        let ok = BodyExtractionResult(
            classifying: ExtractedBody(text: words(600), title: "A page"), source: .tab)
        #expect(ok.status == .ok)
        #expect(ok.body == words(600))
        #expect(ok.source == .tab)
        #expect(ok.title == "A page")

        let thin = BodyExtractionResult(
            classifying: ExtractedBody(text: words(30)), source: .fetch)
        #expect(thin.status == .thin)
        #expect(thin.body == words(30))

        let failed = BodyExtractionResult(classifying: nil, source: .fetch)
        #expect(failed.status == .failed)
        #expect(failed.body == nil)
        #expect(failed.title == nil)
    }
}

private func words(_ count: Int) -> String {
    (0..<count).map { "w\($0)" }.joined(separator: " ")
}
