import Foundation
import Testing

@testable import CapKit

@Suite("FetchPolicy")
struct FetchPolicyTests {
    @Test(
        "Only http and https with a host are fetchable",
        arguments: [
            ("https://example.com/a", true),
            ("http://example.com/a", true),
            ("HTTPS://EXAMPLE.COM/a", true),
            ("ftp://example.com/a", false),
            ("file:///etc/passwd", false),
            ("javascript:alert(1)", false),
            ("data:text/html,hello", false),
            ("mailto:someone@example.com", false),
        ])
    func schemeGate(candidate: String, fetchable: Bool) throws {
        let url = try #require(URL(string: candidate))
        #expect(FetchPolicy.isFetchable(url) == fetchable)
    }

    @Test(
        "Navigation stays locked to the target URL",
        arguments: [
            ("https://example.com/a?x=1", "https://example.com/a?x=1", true),
            ("https://example.com/a?x=1", "https://example.com/a?x=1#section", true),
            ("https://example.com/a", "https://example.com/a/", true),
            ("http://example.com/a", "https://example.com/a", true),
            ("http://example.com:80/a", "http://example.com/a", true),
            ("https://example.com/a", "http://example.com/a", false),
            ("https://example.com/a", "https://other.example.com/a", false),
            ("https://example.com/a", "https://www.example.com/a", false),
            ("https://example.com/a", "https://example.com/b", false),
            ("https://example.com/a?x=1", "https://example.com/a?x=2", false),
            ("https://example.com/a?x=1", "https://example.com/a", false),
            ("http://example.com:8080/a", "http://example.com/a", false),
        ])
    func navigationLock(target: String, candidate: String, allowed: Bool) throws {
        let targetURL = try #require(URL(string: target))
        let candidateURL = try #require(URL(string: candidate))
        #expect(FetchPolicy.allowsNavigation(from: targetURL, to: candidateURL) == allowed)
    }

    @Test("The byte cap trusts a header when present and the snapshot regardless")
    func byteLimits() {
        let limit = FetchPolicy.byteLimit

        #expect(FetchPolicy.withinByteLimit(reportedLength: Int64(limit)))
        #expect(!FetchPolicy.withinByteLimit(reportedLength: Int64(limit) + 1))
        #expect(FetchPolicy.withinByteLimit(reportedLength: -1))

        #expect(FetchPolicy.withinByteLimit(snapshotUTF8Count: limit))
        #expect(!FetchPolicy.withinByteLimit(snapshotUTF8Count: limit + 1))
    }
}
