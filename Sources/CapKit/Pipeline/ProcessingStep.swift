import Foundation

/// What a step may reach beyond the capture row itself.
public struct ProcessingContext: Sendable {
    public let paths: StoragePaths

    public init(paths: StoragePaths) {
        self.paths = paths
    }
}

/// Field updates a step produced; nil means the column is left alone.
public struct StepResult: Sendable, Equatable {
    public var ocrText: String?

    public init(ocrText: String? = nil) {
        self.ocrText = ocrText
    }
}

/// One enrichment a capture may need after ingest.
///
/// Steps are pure — capture in, result out — so they hold no write access to the store
/// and can run in any process.
public protocol ProcessingStep: Sendable {
    func applies(to capture: Capture) -> Bool
    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult
}
