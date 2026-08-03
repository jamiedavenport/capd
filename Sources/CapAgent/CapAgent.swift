import CapKit
import Foundation
import os

/// The background enrichment worker: page fetch, body extraction, OCR, and tagging.
///
/// One binary, three modes: the launchd-supervised agent (no arguments), a short-lived
/// `fetch` child whose WebKit crashes die with it instead of with the agent, and
/// `install`, which points launchd at this executable.
@main
struct CapAgent {
    static let logger = Logger(subsystem: CapKit.bundleIdentifier, category: "agent")

    /// How often the agent looks for pending captures and stale claims. The queries are
    /// indexed and the reclaim writes only when a stale row exists, so the tick is cheap.
    static let pollInterval: Duration = .seconds(3)

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case nil:
            runAgent()
        case "fetch" where arguments.count == 2:
            FetchChild.main(urlString: arguments[1])
        case "install" where arguments.count == 1:
            runInstall()
        default:
            FileHandle.standardError.write(Data("usage: cap-agent [install | fetch <url>]\n".utf8))
            exit(EX_USAGE)
        }
    }

    private static func runInstall() -> Never {
        do {
            try AgentInstaller.install()
            exit(EXIT_SUCCESS)
        } catch {
            FileHandle.standardError.write(Data("cap-agent: install failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func runAgent() -> Never {
        do {
            let paths = try StoragePaths.live
            let store = try Store(paths: paths)

            guard AgentLock.acquire(at: paths.agentLockURL) != nil else {
                logger.notice("another cap-agent holds the lock; exiting")
                exit(EXIT_SUCCESS)
            }

            guard let executable = Bundle.main.executableURL else {
                logger.error("cannot locate own executable")
                exit(EXIT_FAILURE)
            }

            let enrichment = EnrichmentService(
                store: store,
                steps: [FetchChildStep(agentExecutable: executable), OCRStep()])
            let queue = EnrichmentQueue(
                enrichment: enrichment, isOnMainsPower: PowerStatus.isOnMainsPower)
            let tagging = TagService(store: store, tagger: FoundationModelTagger())

            logger.info("cap-agent \(CapKit.version, privacy: .public) started")

            Task {
                // At startup every `fetching` row was abandoned by a crash, except a
                // capture the app is enriching this instant; stealing that one wastes a
                // fetch but the state machine keeps both writers safe.
                await sweep(enrichment: enrichment, olderThan: nil)
                while true {
                    await sweep(enrichment: enrichment, olderThan: EnrichmentService.staleClaimAge)
                    if ((try? enrichment.pendingCount()) ?? 0) > 0 {
                        await queue.drain()
                    }
                    await tag(with: tagging)
                    try? await Task.sleep(for: pollInterval)
                }
            }
            RunLoop.main.run()
            exit(EXIT_SUCCESS)
        } catch {
            let reason = String(describing: error)
            logger.error("cap-agent failed to start: \(reason, privacy: .public)")
            exit(EXIT_FAILURE)
        }
    }

    private static func tag(with tagging: TagService) async {
        do {
            let onMains = PowerStatus.isOnMainsPower()
            let batch = DrainPolicy.width(onMainsPower: onMains)
            let processed = try await tagging.tagNext(batch: batch)
            if processed > 0 {
                logger.info("tagged \(processed) capture(s)")
            }
            // The sweep rewrites rows in bulk, so it waits for mains power.
            if onMains, try await tagging.consolidateIfNeeded() {
                logger.notice("consolidated the tag taxonomy")
            }
        } catch {
            // Transient model failures wait for the next tick; the rows stay queued.
            let reason = String(describing: error)
            logger.error("tagging failed: \(reason, privacy: .public)")
        }
    }

    private static func sweep(enrichment: EnrichmentService, olderThan age: TimeInterval?) async {
        let reclaimed = (try? enrichment.reclaimStale(olderThan: age)) ?? 0
        if reclaimed > 0 {
            logger.notice("reclaimed \(reclaimed) stale enrichment claim(s)")
        }
    }
}

/// One agent per store: the flock is released only by process exit, so a crash can never
/// leave it stuck. The descriptor is deliberately never closed.
struct AgentLock {
    private let descriptor: Int32

    static func acquire(at url: URL) -> AgentLock? {
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return AgentLock(descriptor: descriptor)
    }
}
