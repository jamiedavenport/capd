import AppKit
import CapAppUI

/// Registers the menu-bar item as a drop surface.
///
/// `MenuBarExtra` never exposes its `NSStatusItem`, so the drop view is layered into
/// the status item's window — found by class name, the only handle SwiftUI leaves.
@MainActor
final class StatusItemDropTarget {
    private let dropView = DropTargetView()
    private var installTask: Task<Void, Never>?

    init(onTargeted: @escaping (Bool) -> Void, onDrop: @escaping ([DroppedItem]) -> Void) {
        dropView.onTargeted = onTargeted
        dropView.onDrop = onDrop
    }

    /// Retries because MenuBarExtra creates its window during the first scene update,
    /// after `AppState` starts.
    func install() {
        installTask = Task {
            for _ in 0..<40 {
                if attach() { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func attach() -> Bool {
        guard dropView.superview == nil else { return true }
        guard
            let contentView = NSApp.windows
                .first(where: { $0.className.contains("NSStatusBarWindow") })?
                .contentView
        else { return false }
        dropView.frame = contentView.bounds
        dropView.autoresizingMask = [.width, .height]
        contentView.addSubview(dropView)
        return true
    }
}
