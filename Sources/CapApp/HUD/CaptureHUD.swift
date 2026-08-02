import AppKit
import SwiftUI

@MainActor
@Observable
final class HUDModel {
    var content: HUDContent?
    var streak = 1
    var revision = 0
    var isAnnotating = false
    var isHovering = false
    var note = ""
}

struct CaptureHUDView: View {
    @Bindable var model: HUDModel
    var beginAnnotation: () -> Void
    var saveNote: () -> Void
    var dismiss: () -> Void
    var hoverChanged: (Bool) -> Void

    @FocusState private var noteFieldFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Transparent border around the card so the close button can overhang it.
    static let margin: CGFloat = 8

    private var shape: RoundedRectangle {
        PanelStyle.shape
    }

    var body: some View {
        card
            .overlay(alignment: .topLeading) { closeButton }
            .padding(Self.margin)
            .onHover(perform: hoverChanged)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: symbol, tint: symbolTint, bounce: model.revision)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.opacity)
                    if let detail = model.content?.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .contentTransition(.opacity)
                    }
                    if model.content?.canAnnotate == true, !model.isAnnotating {
                        Text("Click to add a note")
                            .font(.system(size: 11))
                            .foregroundStyle(model.isHovering ? .secondary : .tertiary)
                    }
                }
            }
            if model.isAnnotating {
                TextField("Note", text: $model.note, prompt: Text("Add a note — ⏎ saves"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .focused($noteFieldFocused)
                    .onSubmit(saveNote)
                    .onAppear { noteFieldFocused = true }
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 360, alignment: .leading)
        .background(cardBackground)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(shape)
        .pointerStyle(
            model.content?.canAnnotate == true && !model.isAnnotating ? .link : .default
        )
        .onTapGesture {
            if model.content?.canAnnotate == true, !model.isAnnotating {
                beginAnnotation()
            }
        }
        .onExitCommand(perform: dismiss)
    }

    @ViewBuilder private var cardBackground: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            shape.fill(.regularMaterial)
        }
    }

    @ViewBuilder private var closeButton: some View {
        if model.isHovering, model.content != nil {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.thickMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .offset(x: -7, y: -7)
            .transition(.opacity)
            .accessibilityLabel("Dismiss")
        }
    }

    private var headline: String {
        guard let content = model.content else { return "" }
        return model.streak > 1 ? "\(content.headline) · \(model.streak)" : content.headline
    }

    private var symbol: String {
        switch model.content?.style {
        case .captured, .none: "checkmark"
        case .duplicate: "clock.arrow.circlepath"
        case .blocked: "lock.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var symbolTint: Color {
        switch model.content?.style {
        case .captured, .none: .green
        case .duplicate: .gray
        case .blocked, .failed: .orange
        }
    }
}

/// Borderless so the toast draws its own shape; key-capable so ⏎ and esc reach the
/// note field without activating the app.
private final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Owns the toast window: animates capture outcomes in and out and turns a click
/// into the annotation flow. Display rules live in `HUDPresentation`.
@MainActor
final class HUDPanelController {
    private let model = HUDModel()
    private let saveNote: (Int64, String) -> Void
    private let panel: HUDPanel
    private var hosting: NSHostingView<CaptureHUDView>!
    private var presentation = HUDPresentation()
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var anchorScreen: NSScreen?

    init(saveNote: @escaping (Int64, String) -> Void) {
        self.saveNote = saveNote

        let panel = HUDPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        hosting = NSHostingView(
            rootView: CaptureHUDView(
                model: model,
                beginAnnotation: { [weak self] in self?.beginAnnotation() },
                saveNote: { [weak self] in self?.saveNoteAndDismiss() },
                dismiss: { [weak self] in self?.requestDismiss() },
                hoverChanged: { [weak self] in self?.hoverChanged($0) }))
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.requestDismiss() }
        panel.onResignKey = { [weak self] in self?.annotationLostKey() }
    }

    func show(_ content: HUDContent) {
        apply(presentation.show(content))
        guard presentation.display?.content == content else { return }
        syncModel()
        presentWindow()
        AccessibilityNotification.Announcement(content.headline).post()
    }

    private func beginAnnotation() {
        guard presentation.beginAnnotation() else { return }
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            model.isAnnotating = true
        }
        layout(animated: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func saveNoteAndDismiss() {
        if let id = model.content?.captureID {
            let note = model.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                saveNote(id, note)
            }
        }
        requestDismiss()
    }

    private func requestDismiss() {
        apply(presentation.dismiss())
        if presentation.display == nil {
            hideWindow()
        } else {
            syncModel()
            layout(animated: true)
        }
    }

    private func annotationLostKey() {
        guard presentation.isAnnotating,
            model.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        apply(presentation.abandonAnnotation())
        syncModel()
        layout(animated: true)
    }

    private func hoverChanged(_ hovering: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            model.isHovering = hovering
        }
        apply(presentation.hoverChanged(hovering))
    }

    private func syncModel() {
        guard let display = presentation.display else { return }
        let changed = model.content != display.content || model.streak != display.streak
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            if changed {
                model.revision += 1
            }
            model.content = display.content
            model.streak = display.streak
            model.isAnnotating = presentation.isAnnotating
            if !presentation.isAnnotating {
                model.note = ""
            }
        }
    }

    private func apply(_ action: HUDPresentation.TimerAction) {
        switch action {
        case .none:
            break
        case .stop:
            dismissTask?.cancel()
        case .restart(let duration):
            dismissTask?.cancel()
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.requestDismiss()
            }
        }
    }

    private func presentWindow() {
        hideTask?.cancel()
        hideTask = nil
        if panel.isVisible {
            // A show mid-fade-out cancels the exit and animates back to opaque.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            layout(animated: true)
            return
        }
        anchorScreen = screenUnderMouse()
        layout(animated: false)
        let final = panel.frame
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(NSPoint(x: final.minX, y: final.minY + 10))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(final, display: true)
            }
        }
    }

    private func hideWindow() {
        dismissTask?.cancel()
        hideTask?.cancel()
        let exit = panel.frame.offsetBy(dx: 0, dy: reduceMotion ? 0 : 8)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !reduceMotion {
                panel.animator().setFrame(exit, display: true)
            }
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            panel.orderOut(nil)
            anchorScreen = nil
            model.content = nil
            model.streak = 1
            model.isAnnotating = false
            model.isHovering = false
            model.note = ""
        }
    }

    /// The card keeps a fixed top-right anchor, so growth extends left and down.
    private func layout(animated: Bool) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard let screen = anchorScreen ?? screenUnderMouse() else { return }
        let inset = 16 - CaptureHUDView.margin
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.maxX - size.width - inset,
            y: visible.maxY - size.height - inset,
            width: size.width,
            height: size.height)
        if animated, panel.isVisible, !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
            Task { [weak panel] in
                try? await Task.sleep(for: .milliseconds(200))
                panel?.invalidateShadow()
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// The hotkey fires while the user is working, so the mouse marks the right screen.
    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
