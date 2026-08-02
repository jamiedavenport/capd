import CapKit
import Foundation

/// The parent side of crash isolation: runs one page fetch in a short-lived child
/// process, so a WebKit crash or hang costs that fetch, not the agent.
struct FetchChildStep: ProcessingStep {
    let agentExecutable: URL
    var deadline: Duration = FetchChildStep.defaultDeadline

    /// The fetch timeout plus grace for child startup and JSON teardown.
    static let defaultDeadline: Duration = FetchPolicy.timeout + .seconds(10)

    func applies(to capture: Capture) -> Bool {
        capture.kind == .link && capture.url != nil
    }

    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        guard let url = capture.url else {
            return StepResult()
        }
        return StepResult(bodyExtraction: await fetchInChild(url: url))
    }

    /// Any child misbehavior — crash, hang, garbage output — reads as a failed fetch.
    func fetchInChild(url: String) async -> BodyExtractionResult {
        let executable = agentExecutable
        let deadline = deadline
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: Self.runChild(executable: executable, url: url, deadline: deadline))
            }
        }
    }

    private static func runChild(
        executable: URL, url: String, deadline: Duration
    ) -> BodyExtractionResult {
        let failed = BodyExtractionResult(body: nil, status: .failed, source: .fetch)

        let child = Child()
        child.process.executableURL = executable
        child.process.arguments = ["fetch", url]
        let stdout = Pipe()
        child.process.standardOutput = stdout
        child.process.standardError = FileHandle.nullDevice

        do {
            try child.process.run()
        } catch {
            return failed
        }

        let watchdog = DispatchWorkItem { child.forceTerminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds(deadline), execute: watchdog)
        defer { watchdog.cancel() }

        // The pipe reaches EOF when the child exits or is killed, so neither read blocks
        // past the watchdog.
        let output = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        child.process.waitUntilExit()

        guard child.process.terminationReason == .exit,
            child.process.terminationStatus == EXIT_SUCCESS,
            let result = try? JSONDecoder().decode(BodyExtractionResult.self, from: output)
        else {
            return failed
        }
        return result
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }
}

/// `Process` is documented safe for these calls across threads; the class records that
/// for the compiler.
private final class Child: @unchecked Sendable {
    let process = Process()

    func forceTerminate() {
        guard process.isRunning else { return }
        // SIGKILL, not SIGTERM: the child is disposable and may be arbitrarily wedged.
        kill(process.processIdentifier, SIGKILL)
    }
}

/// The child side: fetch one URL under `FetchPolicy`, print the extraction as JSON, exit.
enum FetchChild {
    static func main(urlString: String) -> Never {
        Task { @MainActor in
            let result: BodyExtractionResult
            if let url = URL(string: urlString) {
                result = await BodyExtractionPipeline().extract(url: url)
            } else {
                result = BodyExtractionResult(body: nil, status: .failed, source: .fetch)
            }
            let output = (try? JSONEncoder().encode(result)) ?? Data()
            FileHandle.standardOutput.write(output)
            exit(EXIT_SUCCESS)
        }
        RunLoop.main.run()
        exit(EXIT_FAILURE)
    }
}
