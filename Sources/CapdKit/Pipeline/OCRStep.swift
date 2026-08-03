import Foundation
import Vision

enum PipelineError: Error, Equatable {
    case missingAsset
}

/// On-device text recognition over an image capture's stored asset.
///
/// An image with no readable text succeeds with an empty string, so the column can tell
/// "ran and found nothing" from "never ran".
public struct OCRStep: ProcessingStep {
    public init() {}

    public func applies(to capture: Capture) -> Bool {
        capture.kind == .image && capture.assetPath != nil
    }

    public func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        guard let assetPath = capture.assetPath else {
            throw PipelineError.missingAsset
        }

        var request = RecognizeTextRequest()
        // Enrichment runs once in the background, so recall beats latency.
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(
            on: context.paths.assetURL(forRelativePath: assetPath))
        let text =
            observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return StepResult(ocrText: text)
    }
}
