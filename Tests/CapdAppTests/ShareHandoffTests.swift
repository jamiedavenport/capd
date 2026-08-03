import Foundation
import Testing

@testable import CapdHandoff

@Suite("ShareHandoff")
struct ShareHandoffTests {
    @Test("A shared page round-trips through the handoff URL")
    func roundTrip() throws {
        let payload = ShareHandoff.Payload(
            url: "https://example.com/a",
            title: "An example page",
            sourceAppBundleID: "com.apple.Safari")

        let url = try #require(ShareHandoff.url(for: payload))
        #expect(ShareHandoff.payload(from: url) == payload)
    }

    @Test("A page URL with its own query and fragment survives the round trip")
    func roundTripPreservesQueryAndFragment() throws {
        let payload = ShareHandoff.Payload(
            url: "https://example.com/watch?v=a1&t=2m30s&x=1+1#top",
            title: "Ampersands & = signs")

        let url = try #require(ShareHandoff.url(for: payload))
        #expect(ShareHandoff.payload(from: url) == payload)
    }

    @Test("A bare link needs no title or source")
    func bareLink() throws {
        let url = try #require(
            ShareHandoff.url(for: ShareHandoff.Payload(url: "https://example.com/a")))

        let payload = try #require(ShareHandoff.payload(from: url))
        #expect(payload.url == "https://example.com/a")
        #expect(payload.title == nil)
        #expect(payload.sourceAppBundleID == nil)
    }

    @Test("Only capd://capture URLs parse")
    func rejectsForeignURLs() {
        for candidate in [
            "https://example.com/capture?url=https%3A%2F%2Fexample.com",
            "capd://search?url=https%3A%2F%2Fexample.com",
            "capd://capture",
            "capd://capture?title=No%20link",
        ] {
            let url = URL(string: candidate)
            #expect(url.flatMap(ShareHandoff.payload(from:)) == nil, "\(candidate)")
        }
    }

    @Test("A handoff to a non-web URL is rejected")
    func rejectsNonWebLinks() {
        for shared in ["file:///etc/passwd", "javascript:alert(1)", "not a url"] {
            let url = ShareHandoff.url(for: ShareHandoff.Payload(url: shared))
            #expect(url.flatMap(ShareHandoff.payload(from:)) == nil, "\(shared)")
        }
    }

    @Test("Whitespace-only titles drop away")
    func blankTitleDrops() throws {
        let url = try #require(
            ShareHandoff.url(
                for: ShareHandoff.Payload(url: "https://example.com/a", title: "  \n")))

        #expect(try #require(ShareHandoff.payload(from: url)).title == nil)
    }
}
