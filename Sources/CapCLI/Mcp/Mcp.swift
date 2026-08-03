import ArgumentParser
import CapKit
import Foundation
import MCP

struct Mcp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve captures to AI assistants over the Model Context Protocol.",
        discussion: """
            Speaks MCP over stdin/stdout and exposes read-only search tools. Register \
            with a client, e.g.:

                claude mcp add cap -- cap mcp
            """)

    func run() async throws {
        let toolbox = McpToolbox(service: SearchService(store: try openStore()))

        let server = Server(
            name: "cap",
            version: CapKit.version,
            capabilities: .init(tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolbox.definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            toolbox.call(name: params.name, arguments: params.arguments ?? [:])
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
