import Foundation
import Testing

@testable import CapdApp

@Suite("Context URL policy")
struct ContextURLPolicyTests {
    @Test("Eligible links carry Capd campaign attribution")
    func attributesLink() throws {
        let input = try #require(URL(string: "https://example.com/article?q=swift#section"))

        let output = CapdLinkAttribution.attributed(input, enabled: true)
        let components = try #require(URLComponents(url: output, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.contains(URLQueryItem(name: "q", value: "swift")) == true)
        #expect(
            components.queryItems?.contains(
                URLQueryItem(name: "utm_source", value: "capd.jxd.dev")) == true)
        #expect(
            components.queryItems?.contains(URLQueryItem(name: "utm_medium", value: "app"))
                == true)
        #expect(components.fragment == "section")
        #expect(CapdLinkAttribution.isAttributed(output))
    }

    @Test("Attribution is opt in")
    func disabledLeavesLinkAlone() throws {
        let input = try #require(URL(string: "https://example.com/article"))
        #expect(CapdLinkAttribution.attributed(input, enabled: false) == input)
    }

    @Test("Existing campaign attribution is never overwritten")
    func existingAttributionSurvives() throws {
        let input = try #require(
            URL(string: "https://example.com/article?utm_source=newsletter&utm_medium=email"))
        #expect(CapdLinkAttribution.attributed(input, enabled: true) == input)
    }

    @Test(
        "Sensitive and local links are not modified",
        arguments: [
            "https://example.com/oauth/authorize?client_id=1",
            "https://example.com/file?X-Amz-Signature=secret",
            "https://example.com/callback?code=secret",
            "http://localhost:8080/article",
            "http://127.0.0.1/article",
            "file:///tmp/article.html",
        ])
    func guardedLinksStayUnchanged(raw: String) throws {
        let input = try #require(URL(string: raw))
        #expect(CapdLinkAttribution.attributed(input, enabled: true) == input)
    }

    @MainActor
    @Test("Local suppression follows the normalized page identity")
    func localSuppressionNormalizes() throws {
        let registry = ContextSuppressionRegistry(lifetime: 30)
        let opened = try #require(URL(string: "https://example.com/article"))
        let attributed = try #require(
            URL(string: "https://example.com/article?utm_source=capd.jxd.dev&utm_medium=app"))
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        registry.register(opened, now: now)

        #expect(registry.contains(attributed, now: now.addingTimeInterval(29)))
        #expect(!registry.contains(attributed, now: now.addingTimeInterval(31)))
    }
}
