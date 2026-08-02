import Foundation
import Testing

@testable import CapAgent
@testable import CapKit

/// The parent side of crash isolation, exercised against stub children: shell scripts
/// standing in for `cap-agent fetch`, so no test touches WebKit or the network.
@Suite("FetchChildStep")
struct FetchChildTests {
    @Test("The child's JSON becomes the extraction result")
    func childOutputIsDecoded() async throws {
        try await withStubChild(
            "echo '{\"body\":\"words from the child\",\"status\":\"ok\",\"source\":\"fetch\"}'"
        ) { step in
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.body == "words from the child")
            #expect(result.status == .ok)
            #expect(result.source == .fetch)
        }
    }

    @Test("A crashing child is a failed fetch, not an agent error")
    func crashingChildFails() async throws {
        try await withStubChild("kill -9 $$") { step in
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .failed)
            #expect(result.body == nil)
        }
    }

    @Test("A child exiting nonzero is a failed fetch")
    func nonzeroExitFails() async throws {
        try await withStubChild("exit 7") { step in
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .failed)
        }
    }

    @Test("Garbage output is a failed fetch")
    func garbageOutputFails() async throws {
        try await withStubChild("echo not json") { step in
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .failed)
        }
    }

    @Test("A hung child is killed at the deadline")
    func hungChildIsKilled() async throws {
        try await withStubChild("sleep 60", deadline: .milliseconds(300)) { step in
            let start = ContinuousClock.now
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .failed)
            #expect(ContinuousClock.now - start < promptReturn)
        }
    }

    @Test("A grandchild keeping the pipe open does not stall the parent")
    func stragglingGrandchildDoesNotStall() async throws {
        try await withStubChild("sleep 60 &\nexit 0") { step in
            let start = ContinuousClock.now
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .failed)
            #expect(ContinuousClock.now - start < promptReturn)
        }
    }

    @Test("Output already written survives a straggling grandchild")
    func writtenOutputSurvivesStraggler() async throws {
        let script = """
            echo '{"body":"words","status":"ok","source":"fetch"}'
            sleep 60 &
            exit 0
            """
        try await withStubChild(script) { step in
            let start = ContinuousClock.now
            let result = await step.fetchInChild(url: "https://example.com/a")
            #expect(result.status == .ok)
            #expect(result.body == "words")
            #expect(ContinuousClock.now - start < promptReturn)
        }
    }

    @Test("The step applies only to link captures with a URL")
    func appliesOnlyToLinks() {
        let step = FetchChildStep(agentExecutable: URL(fileURLWithPath: "/usr/bin/true"))
        let now = Date()

        #expect(step.applies(to: Capture(kind: .link, url: "https://example.com", createdAt: now)))
        #expect(!step.applies(to: Capture(kind: .link, createdAt: now)))
        #expect(!step.applies(to: Capture(kind: .image, createdAt: now)))
        #expect(!step.applies(to: Capture(kind: .text, createdAt: now)))
    }
}

/// A "returned promptly" bound with slack for starved CI runners, yet far below the
/// 60-second sleeps a stalled parent would sit through.
private let promptReturn: Duration = .seconds(30)

private func withStubChild(
    _ script: String,
    deadline: Duration = FetchChildStep.defaultDeadline,
    _ body: (FetchChildStep) async throws -> Void
) async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-fetch-child-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("stub-agent", isDirectory: false)
    try "#!/bin/sh\n\(script)\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: executable.path)

    try await body(FetchChildStep(agentExecutable: executable, deadline: deadline))
}
