import Foundation
import SwiftSoup

/// The salvage tier under Readability: deliberately boring DOM heuristics, no cleverness.
public enum SoupExtractor {
    private static let chrome =
        "script, style, noscript, template, nav, header, footer, aside, form"
    private static let containers = ["article", "main", "[role=main]"]

    public static func extract(html: String, url: URL?) -> ExtractedBody? {
        guard let document = try? SwiftSoup.parse(html, url?.absoluteString ?? "") else {
            return nil
        }

        // Checked before pruning removes forms, or a login page would read as passwordless.
        let hasPasswordField =
            ((try? document.select("input[type=password]"))?.array().isEmpty ?? true) == false
        let title = (try? document.title()).flatMap { $0.isEmpty ? nil : $0 }

        _ = try? document.select(chrome).remove()

        guard let container = mainContainer(of: document),
            let text = (try? container.text())?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }
        return ExtractedBody(text: text, title: title, hasPasswordField: hasPasswordField)
    }

    private static func mainContainer(of document: Document) -> Element? {
        for selector in containers {
            guard let element = try? document.select(selector).first() else { continue }
            if let text = try? element.text(),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return element
            }
        }
        return document.body()
    }
}
