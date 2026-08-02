import CapKit
import Foundation
import os

/// The background enrichment agent.
///
/// The agent drains the capture queue: page fetch, body extraction, and OCR. Its
/// launchd LaunchAgent plist (A1), actor-based queue with a concurrency cap (P1),
/// WebKit child-process isolation, and startup reclamation of stale `fetching` rows
/// (T1) all arrive with the agent ticket. This scaffold establishes only the binary.
@main
struct CapAgent {
    static func main() {
        let logger = Logger(subsystem: CapKit.bundleIdentifier, category: "agent")
        logger.info("cap-agent \(CapKit.version, privacy: .public) started; no queue to drain yet")
    }
}
