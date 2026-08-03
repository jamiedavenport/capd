import AppKit

/// Transparent drag destination layered over the status item and the notch HUD.
///
/// Invisible to clicks — `hitTest` returns nil — so the surface beneath behaves
/// normally until a drag arrives; AppKit routes drags by registered types, not by
/// hit-testing.
final class DropTargetView: NSView {
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([DroppedItem]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DroppedItem.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargeted?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let items = DroppedItem.items(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        onDrop?(items)
        return true
    }
}
