import AppKit
import SwiftUI

/// Borderless so the window is just the search card; key-capable so typing lands in the
/// query field without activating the app, exactly like Spotlight.
private final class SearchPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns the search window: summons it Spotlight-style on the active screen, hands the
/// keyboard to the query field, and dismisses on Escape or on losing focus.
@MainActor
final class SearchWindowController: NSObject, NSWindowDelegate {
    private let model: SearchModel
    private let panel: SearchPanel

    init(environment: SearchEnvironment, favicons: FaviconStore?) {
        model = SearchModel(environment: environment)

        let panel = SearchPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        super.init()

        let hosting = NSHostingView(
            rootView: SearchView(model: model).environment(\.faviconStore, favicons))
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Summons with a short fade-and-settle; dismissal is instant, like Spotlight.
    func show() {
        model.activate()
        position()
        let final = panel.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(NSPoint(x: final.minX, y: final.minY + 8))
        }
        panel.makeKeyAndOrderFront(nil)
        if let contentView = panel.contentView {
            panel.makeFirstResponder(contentView)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(final, display: true)
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Spotlight's spot: horizontally centered, the top edge about a quarter down the screen.
    private func position() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: max(visible.minY, visible.maxY - visible.height * 0.25 - size.height))
        panel.setFrameOrigin(origin)
    }
}
