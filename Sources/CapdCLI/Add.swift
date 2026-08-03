import ArgumentParser
import CapdKit
import Foundation

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a URL or a piece of text.",
        discussion: """
            Reads standard input when the argument is '-'. If every input line is a URL, \
            each line becomes its own capture; anything else is captured whole, as text.
            """)

    @Argument(help: "A URL, text to keep, or '-' to read standard input.")
    var input: String

    @Option(help: "A title to store with the capture.")
    var title: String?

    @Option(help: "A note to store with the capture.")
    var note: String?

    @Flag(help: "Store a link without queueing a page fetch.")
    var noFetch = false

    @Flag(help: "Block until enrichment finishes.")
    var wait = false

    @Option(help: "Seconds --wait holds on before giving up.")
    var timeout = 60

    @Flag(help: "Emit the captured items as a JSON array.")
    var json = false

    func validate() throws {
        if timeout < 0 {
            throw ValidationError("--timeout cannot be negative.")
        }
    }

    func run() throws {
        let store = try openStore()
        let captures = CaptureService(store: store)
        let search = SearchService(store: store)

        let requests = try makeRequests()
        let bulk = requests.count > 1

        var results: [(capture: Capture, previousSeenAt: Date?)] = []
        var failed = false

        for request in requests {
            do {
                switch try captures.ingest(request) {
                case .captured(let capture):
                    results.append((capture, nil))
                case .alreadyCaptured(let capture, let previousSeenAt):
                    results.append((capture, previousSeenAt))
                }
            } catch {
                guard bulk else { throw CLIError.badUsage(describe(error)) }
                failed = true
                printToStderr(describe(error))
            }
        }

        if wait {
            try awaitEnrichment(of: results.map(\.capture), in: search)
            results = try results.map { result in
                guard let id = result.capture.id, let current = try search.capture(id: id)
                else { return result }
                return (current, result.previousSeenAt)
            }
        }

        if json {
            print(try jsonString(results.map(\.capture)))
        } else {
            for (capture, previousSeenAt) in results {
                if let previousSeenAt {
                    let seen = day(previousSeenAt)
                    print("Already captured #\(capture.id ?? 0) (\(seen)): \(headline(capture))")
                } else {
                    print("Captured #\(capture.id ?? 0): \(headline(capture))")
                }
            }
        }

        if failed {
            throw CLIError(message: "", code: 2)
        }
    }

    private func makeRequests() throws -> [CaptureRequest] {
        guard input == "-" else { return [request(for: input)] }

        let data = (try? FileHandle.standardInput.readToEnd()) ?? Data()
        guard let piped = String(data: data, encoding: .utf8) else {
            throw CLIError.badUsage("Standard input is not UTF-8 text.")
        }

        let lines = piped.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty, lines.allSatisfy(LinkDetection.looksLikeURL) {
            return lines.map(request(for:))
        }
        let text = piped.trimmingCharacters(in: .whitespacesAndNewlines)
        return [CaptureRequest(text: text, title: title, note: note, fetchBody: !noFetch)]
    }

    private func request(for content: String) -> CaptureRequest {
        let isURL = LinkDetection.looksLikeURL(content)
        return CaptureRequest(
            url: isURL ? content : nil,
            text: isURL ? nil : content,
            title: title,
            note: note,
            fetchBody: !noFetch)
    }

    private func awaitEnrichment(of captured: [Capture], in search: SearchService) throws {
        var queued = Set(captured.filter { $0.enrichmentState.isQueued }.compactMap(\.id))
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while !queued.isEmpty {
            for id in Array(queued) {
                if let current = try search.capture(id: id), current.enrichmentState.isQueued {
                    continue
                }
                queued.remove(id)
            }
            if queued.isEmpty { break }
            guard Date() < deadline else {
                throw CLIError(
                    message: "Enrichment still queued after \(timeout)s — is capd-agent running?",
                    code: 4)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
