import Foundation

/// Canonicalizes a link for hashing, so that cosmetic variants of one URL dedupe to one
/// capture. The stored `url` column keeps the string as captured; only `content_hash` sees
/// this form.
public enum URLNormalizer {
    private static let trackingPrefixes = ["utm_"]
    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gbraid", "wbraid", "msclkid", "twclid", "dclid",
        "mc_cid", "mc_eid", "igshid",
    ]

    public static func normalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let port = components.port,
            (components.scheme == "http" && port == 80)
                || (components.scheme == "https" && port == 443)
        {
            components.port = nil
        }

        // Percent-encoded accessors on both sides, so normalization never re-encodes what the
        // caller escaped.
        if let items = components.percentEncodedQueryItems {
            let kept =
                items
                .filter { !isTracking($0.name) }
                .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        }

        if components.path.isEmpty {
            components.path = "/"
        }

        return components.string ?? url.absoluteString
    }

    private static func isTracking(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return trackingNames.contains(lowercased)
            || trackingPrefixes.contains { lowercased.hasPrefix($0) }
    }
}
