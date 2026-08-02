import Foundation

/// What ``CaptureService/ingest(_:)`` did with a request.
public enum CaptureOutcome: Sendable, Equatable {
    /// The content was new; a row was inserted.
    case captured(Capture)
    /// The content collided with an existing row, which was updated in place.
    /// `previousSeenAt` is when it was last seen before this re-capture.
    case alreadyCaptured(Capture, previousSeenAt: Date)

    /// The row as persisted, whichever way it got there.
    public var capture: Capture {
        switch self {
        case .captured(let capture), .alreadyCaptured(let capture, previousSeenAt: _):
            capture
        }
    }
}
