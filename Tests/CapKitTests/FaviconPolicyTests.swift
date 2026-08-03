import Foundation
import Testing

@testable import CapKit

@Suite("FaviconPolicy")
struct FaviconPolicyTests {
    @Test(
        "Cache keys share one entry per site",
        arguments: [
            ("example.com", "example.com"),
            ("www.example.com", "example.com"),
            ("WWW.Example.COM", "example.com"),
            ("example.com:8080", "example.com"),
            ("www.example.com:443", "example.com"),
            ("wwwexample.com", "wwwexample.com"),
            ("docs.example.com", "docs.example.com"),
        ])
    func cacheKeys(host: String, expected: String) {
        #expect(FaviconPolicy.cacheKey(forHost: host) == expected)
    }

    @Test("A miss stands for the TTL and then expires")
    func missExpiry() {
        let recorded = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(!FaviconPolicy.isExpired(missRecordedAt: recorded, now: recorded))
        #expect(
            !FaviconPolicy.isExpired(
                missRecordedAt: recorded,
                now: recorded.addingTimeInterval(FaviconPolicy.missTTL - 1)))
        #expect(
            FaviconPolicy.isExpired(
                missRecordedAt: recorded,
                now: recorded.addingTimeInterval(FaviconPolicy.missTTL)))
    }
}
