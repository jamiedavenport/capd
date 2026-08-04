import CapdKit
import Foundation

enum CapdLinkAttribution {
    static let source = "capd.jxd.dev"
    static let medium = "app"

    static func attributed(_ url: URL, enabled: Bool) -> URL {
        guard enabled, isEligible(url),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }

        var items = components.percentEncodedQueryItems ?? []
        guard
            !items.contains(where: { $0.name.caseInsensitiveCompare("utm_source") == .orderedSame })
        else { return url }
        items.append(URLQueryItem(name: "utm_source", value: source))
        items.append(URLQueryItem(name: "utm_medium", value: medium))
        components.percentEncodedQueryItems = items
        return components.url ?? url
    }

    static func isAttributed(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { item in
            item.name.caseInsensitiveCompare("utm_source") == .orderedSame
                && item.value?.caseInsensitiveCompare(source) == .orderedSame
        } == true
    }

    private static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.user == nil, url.password == nil, let host = url.host?.lowercased(),
            !isLocal(host)
        else { return false }

        let sensitiveNames: Set<String> = [
            "access_token", "auth", "code", "credential", "jwt", "key-pair-id", "policy",
            "sig", "signature", "token", "x-amz-credential", "x-amz-signature",
            "x-goog-credential", "x-goog-signature",
        ]
        let names =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .map { $0.name.lowercased() } ?? []
        guard names.allSatisfy({ !sensitiveNames.contains($0) }) else { return false }

        let sensitivePathParts: Set<String> = [
            "authorize", "checkout", "login", "oauth", "payment", "signin",
        ]
        return url.pathComponents.map { $0.lowercased() }
            .allSatisfy { !sensitivePathParts.contains($0) }
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
            || host.hasSuffix(".localhost") || host.hasSuffix(".local")
    }
}

@MainActor
final class ContextSuppressionRegistry {
    private let lifetime: TimeInterval
    private var expirations: [String: Date] = [:]

    init(lifetime: TimeInterval = 30) {
        self.lifetime = lifetime
    }

    func register(_ url: URL, now: Date = Date()) {
        expirations[URLNormalizer.normalize(url)] = now.addingTimeInterval(lifetime)
    }

    func register(capture: Capture, now: Date = Date()) {
        guard let rawURL = capture.url, let url = URL(string: rawURL) else { return }
        register(url, now: now)
    }

    func contains(_ url: URL, now: Date = Date()) -> Bool {
        expirations = expirations.filter { $0.value > now }
        return expirations[URLNormalizer.normalize(url)] != nil
    }
}
