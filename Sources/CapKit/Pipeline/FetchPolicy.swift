import Foundation

/// The hardening rules for the network fetch, kept pure so every rule is testable offline.
public enum FetchPolicy {
    public static let timeout: Duration = .seconds(15)
    public static let byteLimit = 10 * 1024 * 1024

    /// Whether a URL may be fetched at all: http or https with a real host, decided before
    /// any network activity.
    public static func isFetchable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host(), !host.isEmpty
        else {
            return false
        }
        return true
    }

    /// Whether a main-frame navigation away from `target` is the same page: an http→https
    /// upgrade, a trailing-slash difference, or a fragment. Anything else — including a
    /// server redirect to another host or path — is blocked, and the fetch fails retryably.
    public static func allowsNavigation(from target: URL, to candidate: URL) -> Bool {
        guard let targetScheme = target.scheme?.lowercased(),
            let candidateScheme = candidate.scheme?.lowercased()
        else {
            return false
        }
        guard
            candidateScheme == targetScheme
                || (targetScheme == "http" && candidateScheme == "https")
        else {
            return false
        }
        guard target.host()?.lowercased() == candidate.host()?.lowercased() else {
            return false
        }
        guard explicitPort(of: target) == explicitPort(of: candidate) else {
            return false
        }
        guard normalizedPath(of: target) == normalizedPath(of: candidate) else {
            return false
        }
        return query(of: target) == query(of: candidate)
    }

    /// Whether a response header's reported length fits the cap; an unknown length (-1)
    /// passes and is caught by the snapshot check instead.
    public static func withinByteLimit(reportedLength: Int64) -> Bool {
        reportedLength < 0 || reportedLength <= Int64(byteLimit)
    }

    /// The cap measures the rendered document, not wire bytes: it protects extraction and
    /// the database, not bandwidth.
    public static func withinByteLimit(snapshotUTF8Count: Int) -> Bool {
        snapshotUTF8Count <= byteLimit
    }

    private static func explicitPort(of url: URL) -> Int? {
        guard let port = url.port else { return nil }
        switch url.scheme?.lowercased() {
        case "http" where port == 80, "https" where port == 443:
            return nil
        default:
            return port
        }
    }

    private static func normalizedPath(of url: URL) -> String {
        let path = url.path(percentEncoded: true)
        if path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    private static func query(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
    }
}
