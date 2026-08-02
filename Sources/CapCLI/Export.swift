import ArgumentParser
import CapKit
import Foundation

enum ExportFormat: String, CaseIterable, ExpressibleByArgument {
    case json
    case markdown
}

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write every capture to standard output.",
        discussion: """
            JSON carries every stored field and is the lossless format; markdown is a \
            readable bookmarks list.
            """)

    @Option(help: "Export format: json or markdown.")
    var format: ExportFormat = .json

    @Flag(help: "Shorthand for --format json.")
    var json = false

    func run() throws {
        let hits = try SearchService(store: openStore()).search(SearchQuery(limit: .max))
        let captures = hits.map(\.capture)

        switch json ? .json : format {
        case .json:
            print(try jsonString(captures))
        case .markdown:
            for capture in captures {
                print(markdownItem(capture))
            }
        }
    }

    private func markdownItem(_ capture: Capture) -> String {
        var lines: [String] = []
        let stamp = day(capture.createdAt)

        if let url = capture.url {
            lines.append("- [\(escaped(capture.title ?? url))](\(url)) — \(stamp)")
        } else if let title = capture.title {
            lines.append("- \(title) — \(stamp)")
        } else {
            lines.append("- \(stamp)")
        }
        if capture.kind == .image, let assetPath = capture.assetPath {
            lines.append("  asset: \(assetPath)")
        }
        for field in [capture.note, capture.selection] {
            guard let field else { continue }
            for line in field.split(whereSeparator: \.isNewline) {
                lines.append("  > \(line)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func escaped(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
