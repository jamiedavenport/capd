import AppKit
import SwiftUI

private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the first-run window and keeps its permission state fresh while it's on screen.
@MainActor
package final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let model: OnboardingModel
    package var onFinished: (() -> Void)?
    package var onClosed: (() -> Void)?

    private let window: NSWindow
    private var refreshTask: Task<Void, Never>?

    package init(environment: OnboardingEnvironment) {
        model = OnboardingModel(environment: environment)

        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.window = window

        super.init()

        window.contentViewController = NSHostingController(
            rootView: OnboardingView(model: model))
        window.delegate = self
        model.onFinished = { [weak self] in
            self?.onFinished?()
            self?.window.close()
        }
        model.onDeferred = { [weak self] in
            self?.window.close()
        }
    }

    package func show() {
        refreshTask?.cancel()
        model.refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.model.refresh()
            }
        }
    }

    package func noteSearchOpened() {
        model.noteSearchOpened()
    }

    package func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        onClosed?()
    }
}
