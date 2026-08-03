import AppKit
import SwiftUI

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

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Welcome to cap"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        self.window = window

        super.init()

        window.contentViewController = NSHostingController(
            rootView: OnboardingView(model: model))
        window.delegate = self
        model.onFinished = { [weak self] in
            self?.onFinished?()
            self?.window.close()
        }
    }

    package func show() {
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
