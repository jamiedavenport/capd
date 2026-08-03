import AppKit

/// Notices drags anywhere on the system so the notch HUD can offer itself before the
/// cursor reaches a registered drop view.
///
/// AppKit only tells a window about drags already over it. A live session is instead
/// inferred from the drag pasteboard's change count moving while the mouse drags —
/// a listen-only signal that needs no input-monitoring grant.
@MainActor
final class DragMonitor {
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var baseline = NSPasteboard(name: .drag).changeCount
    private var sessionActive = false

    func start() {
        guard monitors.isEmpty else { return }
        // Global monitors miss events delivered to this app and local ones miss
        // everyone else's, so each event needs both.
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                MainActor.assumeIsolated { self?.dragged() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                MainActor.assumeIsolated { self?.dragged() }
                return event
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated { self?.ended() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated { self?.ended() }
                return event
            },
        ].compactMap { $0 }
    }

    private func dragged() {
        guard NSPasteboard(name: .drag).changeCount != baseline else { return }
        sessionActive = true
        onDragMoved?(NSEvent.mouseLocation)
    }

    private func ended() {
        baseline = NSPasteboard(name: .drag).changeCount
        guard sessionActive else { return }
        sessionActive = false
        onDragEnded?()
    }
}
