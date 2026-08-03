import AppKit

/// Transparent drag destination layered over the status item and the notch HUD.
///
/// Invisible to clicks — `hitTest` returns nil — so the surface beneath behaves
/// normally until a drag arrives; AppKit routes drags by registered types, not by
/// hit-testing.
package final class DropTargetView: NSView {
    package var onTargeted: ((Bool) -> Void)?
    package var onDrop: (([DroppedItem]) -> Void)?

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DroppedItem.acceptedTypes)
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    package override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    package override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onTargeted?(true)
        return .copy
    }

    package override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargeted?(false)
    }

    package override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargeted?(false)
    }

    package override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let items = DroppedItem.items(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        onDrop?(items)
        return true
    }
}
