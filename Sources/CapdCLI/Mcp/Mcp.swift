import ArgumentParser
import CapdKit
import Dispatch
import Foundation
import MCP
import Synchronization

struct Mcp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve captures to AI assistants over the Model Context Protocol.",
        discussion: """
            Speaks MCP over stdin/stdout and exposes read-only search tools. Register \
            with a client, e.g.:

                claude mcp add capd -- capd mcp
            """)

    /// Synchronous, bridging to the async server by hand: CapdCLITests links this
    /// executable into the test bundle, and an async entry point anywhere on that path
    /// makes SwiftPM's release-mode test runner execute capd's main instead of the tests.
    func run() throws {
        let service = SearchService(store: try openStore())

        let failure = Mutex<(any Error)?>(nil)
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await Self.serve(service)
            } catch {
                failure.withLock { $0 = error }
            }
            finished.signal()
        }
        finished.wait()
        if let error = failure.withLock({ $0 }) {
            throw error
        }
    }

    private static func serve(_ service: SearchService) async throws {
        let toolbox = McpToolbox(service: service)

        let server = Server(
            name: "capd",
            version: CapdKit.version,
            capabilities: .init(tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolbox.definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await toolbox.call(name: params.name, arguments: params.arguments ?? [:])
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
