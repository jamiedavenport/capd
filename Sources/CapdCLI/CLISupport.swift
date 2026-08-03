import ArgumentParser
import CapdKit
import Darwin
import Foundation

/// A failure carrying one of the CLI's documented exit codes:
/// 0 ok, 1 no results, 2 bad usage, 3 store unavailable, 4 agent not running.
struct CLIError: Error {
    var message: String
    var code: Int32

    static func badUsage(_ message: String) -> CLIError {
        CLIError(message: message, code: 2)
    }

    static func noResults(_ message: String) -> CLIError {
        CLIError(message: message, code: 1)
    }

    func terminate() -> Never {
        if !message.isEmpty {
            printToStderr(message)
        }
        Darwin.exit(code)
    }
}

func printToStderr(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func openStore() throws -> Store {
    do {
        return try Store(paths: .live)
    } catch {
        throw CLIError(message: "The capture store is unavailable: \(describe(error))", code: 3)
    }
}

func describe(_ error: any Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
}

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case plain
    case tsv
    case json
}

struct OutputOptions: ParsableArguments {
    @Option(help: "Output format: plain, tsv, or json.")
    var format: OutputFormat = .plain

    @Flag(help: "Shorthand for --format json.")
    var json = false

    var resolved: OutputFormat { json ? .json : format }
}

/// UTC, fractional seconds kept, so an exported capture re-imports to the same instant.
func timestamp(_ date: Date) -> String {
    date.ISO8601Format(.init(includingFractionalSeconds: true))
}

/// The user's local day, for human-facing lines.
func day(_ date: Date) -> String {
    date.ISO8601Format(.init(timeZone: .current).year().month().day())
}

func makeJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(timestamp(date))
    }
    return encoder
}

func jsonString(_ value: some Encodable) throws -> String {
    String(decoding: try makeJSONEncoder().encode(value), as: UTF8.self)
}

func headline(_ capture: Capture) -> String {
    if let url = capture.url {
        if let title = capture.title, !title.isEmpty {
            return "\(singleLine(title, max: 80)) — \(url)"
        }
        return url
    }
    if let title = capture.title, !title.isEmpty {
        return singleLine(title, max: 80)
    }
    return singleLine(capture.selection ?? capture.note ?? capture.assetPath ?? "", max: 80)
}

func singleLine(_ text: String, max: Int) -> String {
    let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard collapsed.count > max else { return collapsed }
    return String(collapsed.prefix(max)) + "…"
}

struct EncodedHit: Encodable {
    let capture: Capture
    let snippet: String?
    let score: Double?
}

func emit(_ hits: [SearchHit], as format: OutputFormat) throws {
    switch format {
    case .json:
        let encoded = hits.map {
            EncodedHit(capture: $0.capture, snippet: $0.snippet?.text, score: $0.score)
        }
        print(try jsonString(encoded))

    case .tsv:
        for hit in hits {
            let capture = hit.capture
            let fields = [
                capture.id.map(String.init) ?? "",
                timestamp(capture.createdAt),
                capture.kind.rawValue,
                tsvField(capture.url),
                tsvField(capture.title),
                tsvField(hit.snippet?.text),
            ]
            print(fields.joined(separator: "\t"))
        }

    case .plain:
        let bold = isatty(fileno(stdout)) == 1
        for hit in hits {
            let capture = hit.capture
            print("#\(capture.id ?? 0)  \(day(capture.createdAt))  \(headline(capture))")
            if let snippet = hit.snippet {
                print("    \(rendered(snippet, bold: bold))")
            }
        }
    }
}

func tsvField(_ value: String?) -> String {
    guard let value else { return "" }
    var escaped = ""
    for character in value {
        switch character {
        case "\\": escaped += "\\\\"
        case "\t": escaped += "\\t"
        case "\n": escaped += "\\n"
        case "\r": escaped += "\\r"
        default: escaped.append(character)
        }
    }
    return escaped
}

private func rendered(_ snippet: Snippet, bold: Bool) -> String {
    var line = ""
    if bold && !snippet.highlights.isEmpty {
        let text = snippet.text
        var cursor = text.startIndex
        for range in snippet.highlights where range.lowerBound >= cursor {
            line += text[cursor..<range.lowerBound]
            line += "\u{1B}[1m\(text[range])\u{1B}[0m"
            cursor = range.upperBound
        }
        line += text[cursor...]
    } else {
        line = snippet.text
    }
    return String(line.map { $0.isNewline || $0 == "\t" ? " " : $0 })
}
