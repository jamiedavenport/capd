import CapKit
import Foundation
import MCP

/// The MCP tool surface: each definition lives next to its handler so the schema the
/// client sees and the arguments the handler reads cannot drift apart.
struct McpToolbox: Sendable {
    let service: SearchService
    private let parser = QueryParser()

    /// Smaller than the CLI's 50: results land in a model's context window, where a
    /// screenful of hits is signal and three are noise.
    static let searchLimit = 20
    static let recentLimit = 10

    var definitions: [Tool] {
        [Self.searchCaptures, Self.getCapture, Self.listRecent].map { entry in
            var tool = entry.tool
            tool.annotations.readOnlyHint = true
            return tool
        }
    }

    func call(name: String, arguments: [String: Value]) -> CallTool.Result {
        let entries = [Self.searchCaptures, Self.getCapture, Self.listRecent]
        guard let entry = entries.first(where: { $0.tool.name == name }) else {
            return Self.failure("Unknown tool '\(name)'.")
        }
        do {
            return try entry.handler(self, arguments)
        } catch let error as CLIError {
            return Self.failure(error.message)
        } catch {
            return Self.failure(describe(error))
        }
    }

    private struct Entry: Sendable {
        let tool: Tool
        let handler: @Sendable (McpToolbox, [String: Value]) throws -> CallTool.Result
    }

    private static let searchCaptures = Entry(
        tool: Tool(
            name: "search_captures",
            description: """
                Full-text search over the user's saved captures (links, text, and \
                screenshots with OCR). Matches titles, hosts, notes, selected text, \
                fetched page bodies, OCR text, and URL substrings. Returns compact \
                hits ranked by relevance; call get_capture for a hit's full page text.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            """
                            Search text. May carry inline filters that also exist as \
                            parameters: site:example.com, since:YYYY-MM-DD, \
                            until:YYYY-MM-DD.
                            """),
                    ]),
                    "site": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only captures from this host or its subdomains."),
                    ]),
                    "since": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only captures on or after this day (YYYY-MM-DD)."),
                    ]),
                    "until": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only captures on or before this day (YYYY-MM-DD)."),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of hits."),
                        "default": .int(searchLimit),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ])),
        handler: { toolbox, arguments in try toolbox.search(arguments) })

    private static let getCapture = Entry(
        tool: Tool(
            name: "get_capture",
            description: """
                Fetch one capture by id with every stored field, including the full \
                extracted page body and OCR text that search hits omit.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("integer"),
                        "description": .string("A capture id from search_captures or list_recent."),
                    ])
                ]),
                "required": .array([.string("id")]),
            ])),
        handler: { toolbox, arguments in try toolbox.get(arguments) })

    private static let listRecent = Entry(
        tool: Tool(
            name: "list_recent",
            description: "The user's most recent captures, newest first.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of captures."),
                        "default": .int(recentLimit),
                    ])
                ]),
            ])),
        handler: { toolbox, arguments in try toolbox.recent(arguments) })

    private func search(_ arguments: [String: Value]) throws -> CallTool.Result {
        let raw = arguments["query"]?.stringValue ?? ""
        var query = parser.parse(raw, limit: arguments["limit"]?.intValue ?? Self.searchLimit)

        if let site = arguments["site"]?.stringValue {
            query.site = site.lowercased()
        }
        if let since = arguments["since"]?.stringValue {
            guard let start = parser.inclusiveDayStart(since) else {
                return Self.failure("'since' expects a real YYYY-MM-DD day, got '\(since)'.")
            }
            query.createdAfter = start
        }
        if let until = arguments["until"]?.stringValue {
            guard let end = parser.exclusiveDayEnd(until) else {
                return Self.failure("'until' expects a real YYYY-MM-DD day, got '\(until)'.")
            }
            query.createdBefore = end
        }

        return try Self.success(service.search(query).map(Hit.init))
    }

    private func get(_ arguments: [String: Value]) throws -> CallTool.Result {
        guard let id = arguments["id"]?.intValue else {
            return Self.failure("'id' expects a capture id, an integer.")
        }
        guard let capture = try service.capture(id: Int64(id)) else {
            return Self.failure("No capture #\(id).")
        }
        return try Self.success(capture)
    }

    private func recent(_ arguments: [String: Value]) throws -> CallTool.Result {
        let query = SearchQuery(limit: arguments["limit"]?.intValue ?? Self.recentLimit)
        return try Self.success(service.search(query).map(Hit.init))
    }

    /// The compact per-hit shape; field names match the CLI's stable `--json` interface.
    private struct Hit: Encodable {
        let id: Int64?
        let kind: CaptureKind
        let url: String?
        let host: String?
        let title: String?
        let note: String?
        let snippet: String?
        let createdAt: Date
        let lastSeenAt: Date
        let seenCount: Int

        init(_ hit: SearchHit) {
            id = hit.capture.id
            kind = hit.capture.kind
            url = hit.capture.url
            host = hit.capture.host
            title = hit.capture.title
            note = hit.capture.note
            snippet = hit.snippet?.text
            createdAt = hit.capture.createdAt
            lastSeenAt = hit.capture.lastSeenAt
            seenCount = hit.capture.seenCount
        }

        enum CodingKeys: String, CodingKey {
            case id
            case kind
            case url
            case host
            case title
            case note
            case snippet
            case createdAt = "created_at"
            case lastSeenAt = "last_seen_at"
            case seenCount = "seen_count"
        }
    }

    private static func success(_ payload: some Encodable) throws -> CallTool.Result {
        .init(
            content: [.text(text: try jsonString(payload), annotations: nil, _meta: nil)],
            isError: false)
    }

    private static func failure(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}
