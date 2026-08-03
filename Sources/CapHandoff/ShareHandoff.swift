import Foundation

/// The `cap://capture` URL that carries a shared page from the share extension — or any
/// outside caller — into the app.
public enum ShareHandoff {
    public static let scheme = "cap"
    static let host = "capture"

    /// What a handoff carries. `url` stays a `String` because ingest owns link
    /// classification, matching `CaptureRequest`.
    public struct Payload: Equatable, Sendable {
        public var url: String
        public var title: String?
        public var sourceAppBundleID: String?

        public init(url: String, title: String? = nil, sourceAppBundleID: String? = nil) {
            self.url = url
            self.title = title
            self.sourceAppBundleID = sourceAppBundleID
        }
    }

    public static func url(for payload: Payload) -> URL? {
        var items = [URLQueryItem(name: "url", value: payload.url)]
        if let title = payload.title {
            items.append(URLQueryItem(name: "title", value: title))
        }
        if let source = payload.sourceAppBundleID {
            items.append(URLQueryItem(name: "source", value: source))
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        // URLComponents leaves `&` and `=` bare inside query values, so a shared URL's
        // own query string would split this one apart on parse. Encoding delimiters by
        // hand keeps the round trip exact.
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(
                name: $0.name,
                value: $0.value?.addingPercentEncoding(withAllowedCharacters: .handoffQueryValue))
        }
        return components.url
    }

    /// Rejects anything but a well-formed `cap://capture` link to a web URL: the scheme
    /// is open to any caller, so this is the trust boundary.
    public static func payload(from url: URL) -> Payload? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme,
            components.host?.lowercased() == host
        else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard
                let value = items.first(where: { $0.name == name })?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else { return nil }
            return value
        }

        guard let shared = value("url"),
            let sharedScheme = URL(string: shared)?.scheme?.lowercased(),
            sharedScheme == "http" || sharedScheme == "https"
        else { return nil }
        return Payload(url: shared, title: value("title"), sourceAppBundleID: value("source"))
    }
}

extension CharacterSet {
    fileprivate static let handoffQueryValue: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }()
}
