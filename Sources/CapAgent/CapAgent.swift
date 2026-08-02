import CapKit
import Foundation
import os

/// The background enrichment worker: page fetch, body extraction, and OCR.
@main
struct CapAgent {
    static func main() {
        let logger = Logger(subsystem: CapKit.bundleIdentifier, category: "agent")
        logger.info("cap-agent \(CapKit.version, privacy: .public) started")
    }
}
