import Foundation
import Testing

/// One scripted MCP session against a live `capd mcp` process. Each response is read
/// before the next request is sent: the stdio transport stops at EOF without draining
/// what is still buffered, so a fire-everything-then-close script loses replies.
@Suite("capd mcp", .timeLimit(.minutes(1)))
struct CLIMcpTests {
    @Test("Tools round-trip over MCP stdio")
    func stdioSession() throws {
        try withScratchRoot { root in
            _ = try capd(
                [
                    "add", "https://example.com/swift-concurrency",
                    "--title", "Swift Concurrency Notes", "--no-fetch",
                ], root: root)

            let process = Process()
            process.executableURL = capdBinary
            process.arguments = ["mcp"]
            var environment = ProcessInfo.processInfo.environment
            environment["CAPD_DIR"] = root.path
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()

            let writer = input.fileHandleForWriting
            let reader = output.fileHandleForReading
            var buffer = Data()

            func send(_ line: String) {
                writer.write(Data((line + "\n").utf8))
            }
            func roundTrip(_ line: String) throws -> [String: Any] {
                send(line)
                return try jsonObject(nextLine(from: reader, buffer: &buffer))
            }
            func result(_ response: [String: Any]) throws -> [String: Any] {
                try #require(response["result"] as? [String: Any])
            }
            func firstText(_ response: [String: Any]) throws -> String {
                let content = try #require(result(response)["content"] as? [[String: Any]])
                return try #require(content.first?["text"] as? String)
            }

            let initialized = try roundTrip(
                """
                {"jsonrpc":"2.0","id":1,"method":"initialize","params":\
                {"protocolVersion":"2025-03-26","capabilities":{},\
                "clientInfo":{"name":"test","version":"0"}}}
                """)
            let serverInfo = try result(initialized)["serverInfo"] as? [String: Any]
            #expect(serverInfo?["name"] as? String == "capd")

            send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

            let listed = try roundTrip(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
            let tools = try #require(result(listed)["tools"] as? [[String: Any]])
            #expect(
                tools.compactMap { $0["name"] as? String }
                    == ["search_captures", "get_capture", "list_recent", "ask_cap"])

            let searched = try roundTrip(
                """
                {"jsonrpc":"2.0","id":3,"method":"tools/call","params":\
                {"name":"search_captures","arguments":{"query":"concurrency"}}}
                """)
            #expect(try result(searched)["isError"] as? Bool == false)
            let hits = try jsonArray(firstText(searched))
            #expect(hits.count == 1)
            #expect(hits.first?["url"] as? String == "https://example.com/swift-concurrency")
            #expect(hits.first?["created_at"] is String)

            let fetched = try roundTrip(
                """
                {"jsonrpc":"2.0","id":4,"method":"tools/call","params":\
                {"name":"get_capture","arguments":{"id":1}}}
                """)
            let capture = try jsonObject(firstText(fetched))
            #expect(capture["url"] as? String == "https://example.com/swift-concurrency")
            #expect(capture["enrichment_state"] is String)

            let missing = try roundTrip(
                """
                {"jsonrpc":"2.0","id":5,"method":"tools/call","params":\
                {"name":"get_capture","arguments":{"id":999}}}
                """)
            #expect(try result(missing)["isError"] as? Bool == true)

            let recent = try roundTrip(
                """
                {"jsonrpc":"2.0","id":6,"method":"tools/call","params":\
                {"name":"list_recent","arguments":{}}}
                """)
            #expect(try jsonArray(firstText(recent)).count == 1)

            try writer.close()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
    }

    private struct ServerClosedStream: Error {}

    private func nextLine(from handle: FileHandle, buffer: inout Data) throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: line, as: UTF8.self)
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { throw ServerClosedStream() }
            buffer.append(chunk)
        }
    }
}
