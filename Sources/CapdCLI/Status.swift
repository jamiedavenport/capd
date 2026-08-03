import ArgumentParser
import CapdKit
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report queue depth, store size, and agent health.",
        discussion: "Exits 4 when no enrichment agent is running against this store.")

    @Flag(help: "Emit the report as JSON.")
    var json = false

    /// Stands in for the measured average until enough enrichments have completed.
    static let assumedSecondsPerCapture = 5.0

    func run() throws {
        let store = try openStore()
        let counts = try store.enrichmentCounts()
        let pending = counts[.pending, default: 0]
        let fetching = counts[.fetching, default: 0]
        let depth = pending + fetching

        let report = StatusReport(
            agent: .init(
                installed: AgentAdmin.isInstalled(),
                loaded: AgentAdmin.isLoaded(),
                running: AgentAdmin.isRunning(paths: store.paths)),
            captures: .init(
                failed: counts[.failed, default: 0],
                fetching: fetching,
                ok: counts[.ok, default: 0],
                pending: pending,
                thin: counts[.thin, default: 0],
                total: counts.values.reduce(0, +)),
            databaseBytes: store.databaseBytes(),
            queue: .init(
                depth: depth,
                etaSeconds: depth > 0
                    ? Self.eta(depth: depth, average: try store.averageEnrichmentSeconds())
                    : nil))

        if json {
            print(try jsonString(report))
        } else {
            print(plainText(report))
        }

        guard report.agent.running else {
            throw CLIError(message: "The enrichment agent is not running.", code: 4)
        }
    }

    static func eta(depth: Int, average: Double?) -> Int {
        // Floored at half a second so sub-millisecond test enrichments never round to 0.
        let perCapture = max(average ?? assumedSecondsPerCapture, 0.5)
        let width = DrainPolicy.width(onMainsPower: PowerStatus.isOnMainsPower())
        return Int((Double(depth) * perCapture / Double(width)).rounded(.up))
    }

    private func plainText(_ report: StatusReport) -> String {
        var lines: [String] = []

        let captures = report.captures
        let outcomes = [
            (captures.ok, "ok"), (captures.thin, "thin"), (captures.failed, "failed"),
        ]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)" }
        lines.append(
            "Captures: \(captures.total)"
                + (outcomes.isEmpty ? "" : " (\(outcomes.joined(separator: ", ")))"))

        if report.queue.depth == 0 {
            lines.append("Queue: empty")
        } else {
            let work = [(captures.pending, "pending"), (captures.fetching, "fetching")]
                .filter { $0.0 > 0 }
                .map { "\($0.0) \($0.1)" }
            var line = "Queue: \(work.joined(separator: ", "))"
            if let eta = report.queue.etaSeconds {
                line += " — ETA ~\(duration(eta))"
            }
            lines.append(line)
        }

        lines.append(
            "Database: "
                + ByteCountFormatter.string(
                    fromByteCount: report.databaseBytes, countStyle: .file))
        lines.append("Agent: \(describeAgent(report.agent))")
        return lines.joined(separator: "\n")
    }

    private func describeAgent(_ agent: StatusReport.Agent) -> String {
        switch (agent.running, agent.loaded, agent.installed) {
        case (true, true, _):
            "running"
        case (true, false, _):
            "running (launchd not loaded)"
        case (false, true, _):
            "not running (launchd loaded)"
        case (false, false, true):
            "not running (installed but not loaded — run `capd doctor`)"
        case (false, false, false):
            "not installed — run `capd doctor`"
        }
    }

    private func duration(_ seconds: Int) -> String {
        seconds < 90 ? "\(seconds)s" : "\(Int((Double(seconds) / 60).rounded()))m"
    }
}

struct StatusReport: Encodable {
    struct Agent: Encodable {
        let installed: Bool
        let loaded: Bool
        let running: Bool
    }

    struct Captures: Encodable {
        let failed: Int
        let fetching: Int
        let ok: Int
        let pending: Int
        let thin: Int
        let total: Int
    }

    struct Queue: Encodable {
        let depth: Int
        let etaSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case depth
            case etaSeconds = "eta_seconds"
        }
    }

    let agent: Agent
    let captures: Captures
    let databaseBytes: Int64
    let queue: Queue

    enum CodingKeys: String, CodingKey {
        case agent
        case captures
        case databaseBytes = "database_bytes"
        case queue
    }
}
