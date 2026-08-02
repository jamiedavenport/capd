import AppKit
import Carbon.HIToolbox

enum PasteboardSkipReason: Equatable {
    case promisedContent
    case tooLarge

    var explanation: String {
        switch self {
        case .promisedContent: "the clipboard holds promised files cap can't restore"
        case .tooLarge: "the clipboard is too large to restore safely"
        }
    }
}

enum PasteboardFallbackResult: Equatable {
    case text(String)
    case image(Data)
    /// ⌘C changed nothing — the frontmost app had no selection to copy.
    case nothing
    case skipped(PasteboardSkipReason)
}

/// Grabs the frontmost app's selection by pressing ⌘C for the user, without losing what
/// was on their clipboard.
struct PasteboardFallback {
    @MainActor
    func copySelection(timeout: Duration = .milliseconds(600)) async -> PasteboardFallbackResult {
        let pasteboard = NSPasteboard.general

        let snapshot: PasteboardSnapshot
        switch PasteboardSnapshot.snapshot(of: pasteboard) {
        case .failure(.promisedContent): return .skipped(.promisedContent)
        case .failure(.tooLarge): return .skipped(.tooLarge)
        case .success(let taken): snapshot = taken
        }

        let before = pasteboard.changeCount
        postCommandC()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while pasteboard.changeCount == before, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard pasteboard.changeCount != before else { return .nothing }

        let result = read(pasteboard)
        snapshot.restore(to: pasteboard)
        return result
    }

    private func read(_ pasteboard: NSPasteboard) -> PasteboardFallbackResult {
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .text(trimmed)
            }
        }
        if let png = pngData(from: pasteboard) {
            return .image(png)
        }
        return .nothing
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        guard let tiff = pasteboard.data(forType: .tiff),
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
