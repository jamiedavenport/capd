import ArgumentParser
import CapKit
import Dispatch
import Foundation
import MCP

struct Mcp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve captures to AI assistants over the Model Context Protocol.",
        discussion: """
            Speaks MCP over stdin/stdout and exposes read-only search tools. Register \
            with a client, e.g.:

                claude mcp add cap -- cap mcp
            """)

    /// Synchronous, bridging to the async server by hand: CapCLITests links this
    /// executable into the test bundle, and an async entry point anywhere on that path
    /// makes SwiftPM's release-mode test runner execute cap's main instead of the tests.
    func run() throws {
        let service = SearchService(store: try openStore())

        nonisolated(unsafe) var failure: (any Error)?
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await Self.serve(service)
            } catch {
                failure = error
            }
            finished.signal()
        }
        finished.wait()
        if let failure {
            throw failure
        }
    }

    private static func serve(_ service: SearchService) async throws {
        let toolbox = McpToolbox(service: service)

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
