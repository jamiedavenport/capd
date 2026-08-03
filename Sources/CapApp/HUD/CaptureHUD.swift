import AppKit
import CapKit
import SwiftUI

@MainActor
@Observable
final class HUDModel {
    /// Which physical top-of-screen form the bar takes. On a notched display the bar
    /// wraps the notch, content split across its flanks; everywhere else it's a pill
    /// hanging from the menu bar.
    enum Variant: Equatable {
        case notch(gap: CGFloat, height: CGFloat)
        case pill
    }

    var content: HUDContent?
    var variant: Variant = .pill
    var streak = 1
    var revision = 0
    var isAnnotating = false
    var isHovering = false
    var revealed = false
    var note = ""
}

struct CaptureHUDView: View {
    @Bindable var model: HUDModel
    var beginAnnotation: () -> Void
    var saveNote: () -> Void
    var dismiss: () -> Void
    var hoverChanged: (Bool) -> Void

    @FocusState private var noteFieldFocused: Bool

    /// Flush with the screen's top edge; only the bottom corners are drawn.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 14,
            topTrailingRadius: 0,
            style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            barRow
            if model.isAnnotating {
                annotationDrawer
            }
        }
        .background(Theme.bar)
        .clipShape(shape)
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
        .onHover(perform: hoverChanged)
        .help(
            model.content?.canAnnotate == true && !model.isAnnotating
                ? "Click to add a note" : "")
    }

    @ViewBuilder private var barRow: some View {
        switch model.variant {
        case .notch(let gap, let height):
            HStack(spacing: 0) {
                flank(.leading) {
                    source.offset(x: model.revealed ? 0 : 56)
                }
                Color.clear.frame(width: gap + 12)
                flank(.trailing) {
                    outcome.offset(x: model.revealed ? 0 : -56)
                }
            }
            .frame(height: height + 6)
        case .pill:
            HStack(spacing: 10) {
                outcome
                separatorDot
                source
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
    }

    /// Both flanks measure both contents invisibly so they end up the same width and
    /// the notch gap stays centered on the physical notch.
    private func flank(_ alignment: Alignment, @ViewBuilder content: () -> some View)
        -> some View
    {
        ZStack(alignment: alignment) {
            source.hidden()
            outcome.hidden()
            content()
        }
        .padding(.horizontal, 14)
    }

    private var source: some View {
        HStack(spacing: 7) {
            IconTile(symbol: kindSymbol, tint: kindTint, size: 17)
            Text(sourceLine ?? "cap")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 190, alignment: .leading)
                .contentTransition(.opacity)
        }
    }

    private var outcome: some View {
        HStack(spacing: 8) {
            Text(headline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .contentTransition(.numericText())
            statusBadge
        }
    }

    /// The outcome badge doubles as the dismiss button while the pointer is on the bar.
    @ViewBuilder private var statusBadge: some View {
        if model.isHovering, !model.isAnnotating {
            Button(action: dismiss) {
                badgeCircle(symbol: "xmark", tint: .gray)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        } else {
            badgeCircle(symbol: symbol, tint: symbolTint)
        }
    }

    private func badgeCircle(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .symbolEffect(.bounce, value: model.revision)
            .frame(width: 14, height: 14)
            .background(tint.gradient, in: Circle())
    }

    private var separatorDot: some View {
        Circle()
            .fill(Theme.textTertiary)
            .frame(width: 3, height: 3)
    }

    private var annotationDrawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = model.content?.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            TextField(
                "Note", text: $model.note,
                prompt: Text("Add a note — ⏎ saves").foregroundStyle(Theme.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .tint(Theme.text)
            .focused($noteFieldFocused)
            .onSubmit(saveNote)
            .onAppear { noteFieldFocused = true }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 300)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var headline: String {
        guard let content = model.content else { return "" }
        return model.streak > 1 ? "\(content.headline) · \(model.streak)" : content.headline
    }

    private var sourceLine: String? {
        model.content?.detail?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
    }

    private var kindSymbol: String {
        switch model.content?.kind {
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .none: "bookmark"
        }
    }

    private var kindTint: Color {
        switch model.content?.kind {
        case .link: .blue
        case .text: .orange
        case .image: .purple
        case .none: .gray
        }
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
        case .captured, .none: Theme.success
        case .duplicate: .gray
        case .blocked, .failed: Theme.warning
        }
    }
}

/// Borderless so the bar draws its own shape; key-capable so ⏎ and esc reach the
/// note field without activating the app. Frames are left unconstrained so the bar
/// may sit flush with the screen edge, inside the notch's menu-bar band.
private final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Owns the bar window: animates capture outcomes in and out and turns a click
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
        panel.appearance = NSAppearance(named: .darkAqua)
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
        if !panel.isVisible {
            configureVariant()
        }
        syncModel()
        presentWindow()
        AccessibilityNotification.Announcement(content.headline).post()
    }

    /// Picked once per appearance so the bar doesn't jump forms mid-display: the
    /// notch wrap on a notched screen, the menu-bar pill everywhere else.
    private func configureVariant() {
        let screen = screenUnderMouse()
        anchorScreen = screen
        if let screen,
            screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
            let gap = screen.frame.width - left.width - right.width
            model.variant = .notch(gap: gap, height: screen.safeAreaInsets.top)
        } else {
            model.variant = .pill
        }
    }

    private func beginAnnotation() {
        guard presentation.beginAnnotation() else { return }
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : Theme.spring) {
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
            withAnimation(reduceMotion ? nil : Theme.spring) {
                model.revealed = true
            }
            layout(animated: true)
            return
        }
        model.revealed = false
        layout(animated: false)
        let final = panel.frame
        panel.alphaValue = 0
        // The pill drops out from under the menu bar; the notch bar stays put and its
        // content slides out from behind the notch instead.
        if case .pill = model.variant, !reduceMotion {
            panel.setFrameOrigin(NSPoint(x: final.minX, y: final.minY + 10))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(final, display: true)
            }
        }
        if reduceMotion {
            model.revealed = true
        } else {
            withAnimation(Theme.spring) {
                model.revealed = true
            }
        }
    }

    private func hideWindow() {
        dismissTask?.cancel()
        hideTask?.cancel()
        let exit = panel.frame.offsetBy(dx: 0, dy: reduceMotion ? 0 : 8)
        if !reduceMotion {
            withAnimation(.easeIn(duration: 0.15)) {
                model.revealed = false
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if case .pill = model.variant, !reduceMotion {
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
            model.revealed = false
            model.note = ""
        }
    }

    /// Top-center anchor: the bar hugs the top edge (notch) or the menu bar's lower
    /// edge (pill), and annotation growth extends downward.
    private func layout(animated: Bool) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard let screen = anchorScreen ?? screenUnderMouse() else { return }
        let top: CGFloat
        switch model.variant {
        case .notch:
            top = screen.frame.maxY
        case .pill:
            top = screen.visibleFrame.maxY
        }
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: top - size.height,
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
