import AppKit
import CapdKit
import KeyboardShortcuts
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
    var isDropTarget = false
    var isDropHovered = false
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
                ? "Click or press \(annotateShortcutLabel) to add a note" : "")
    }

    @ViewBuilder private var barRow: some View {
        switch model.variant {
        case .notch(let gap, let height):
            HStack(spacing: 0) {
                flank(.leading) {
                    Group {
                        if model.isDropTarget {
                            dropInvite
                        } else {
                            source
                        }
                    }
                    .offset(x: model.revealed ? 0 : 56)
                }
                Color.clear.frame(width: gap + 12)
                flank(.trailing) {
                    Group {
                        if model.isDropTarget {
                            dropKinds
                        } else {
                            outcome
                        }
                    }
                    .offset(x: model.revealed ? 0 : -56)
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
            if model.isDropTarget {
                dropInvite.hidden()
                dropKinds.hidden()
            } else {
                source.hidden()
                outcome.hidden()
            }
            content()
        }
        .padding(.horizontal, 14)
    }

    /// The bar's face while a drag is overhead: an invitation on one flank, the
    /// accepted kinds on the other.
    private var dropInvite: some View {
        HStack(spacing: 7) {
            IconTile(
                symbol: "arrow.down",
                tint: model.isDropHovered ? Theme.success : .blue,
                size: 17)
            Text("Drop to capture")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
    }

    private var dropKinds: some View {
        HStack(spacing: 9) {
            ForEach(["link", "text.alignleft", "photo"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.isDropHovered ? Theme.text : Theme.textTertiary)
            }
        }
    }

    private var source: some View {
        HStack(spacing: 7) {
            FaviconTile(
                host: model.content?.host,
                fallbackSymbol: kindSymbol,
                fallbackTint: kindTint,
                size: 17)
            Text(sourceLine ?? "Capd")
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
            if model.content?.canAnnotate == true, !model.isAnnotating {
                ShortcutHint(label: "Note", keys: [annotateShortcutLabel])
                    .font(.system(size: 11))
                    .transition(.opacity)
            }
        }
    }

    private var annotateShortcutLabel: String {
        KeyboardShortcuts.getShortcut(for: .annotate).map { "\($0)" } ?? "⌃⌥N"
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
        case .copied: "doc.on.doc"
        case .duplicate: "clock.arrow.circlepath"
        case .insight: "sparkles"
        case .blocked: "lock.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var symbolTint: Color {
        switch model.content?.style {
        case .captured, .copied, .none: Theme.success
        case .duplicate: .gray
        case .insight: Theme.accent
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
package final class HUDPanelController {
    private let model = HUDModel()
    private let saveNote: (Int64, String) -> Void
    private let panel: HUDPanel
    private var hosting: NSHostingView<AnyView>!
    private var presentation = HUDPresentation()
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var anchorScreen: NSScreen?

    /// Where dropped items go; set once the capture path exists.
    package var performDrop: (([DroppedItem]) -> Void)?
    private let dropView = DropTargetView()
    private var dropGeometry: NotchGeometry?
    /// A drop landed and its outcome toast hasn't arrived yet; the bar keeps its
    /// drop face so the handoff doesn't flash an empty bar.
    private var dropPending = false
    private var dropWithdrawTask: Task<Void, Never>?

    package init(favicons: FaviconStore?, saveNote: @escaping (Int64, String) -> Void) {
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
            rootView: AnyView(
                CaptureHUDView(
                    model: model,
                    beginAnnotation: { [weak self] in self?.beginAnnotation() },
                    saveNote: { [weak self] in self?.saveNoteAndDismiss() },
                    dismiss: { [weak self] in self?.requestDismiss() },
                    hoverChanged: { [weak self] in self?.hoverChanged($0) }
                )
                .environment(\.faviconStore, favicons)))
        // A plain container rather than the hosting view itself, so the drop overlay
        // never has to live inside NSHostingView's managed hierarchy.
        let container = NSView()
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.onCancel = { [weak self] in self?.requestDismiss() }
        panel.onResignKey = { [weak self] in self?.annotationLostKey() }

        dropView.onTargeted = { [weak self] in self?.dropHoverChanged($0) }
        dropView.onDrop = { [weak self] in self?.completeDrop($0) }
    }

    package func show(_ content: HUDContent) {
        apply(presentation.show(content))
        if dropGeometry != nil {
            // The bar is busy being a drop target; the toast takes over on withdrawal.
            dismissTask?.cancel()
            return
        }
        if dropPending || model.isDropTarget {
            dropPending = false
            withAnimation(reduceMotion ? nil : Theme.spring) {
                model.isDropTarget = false
                model.isDropHovered = false
            }
        }
        guard presentation.display?.content == content else { return }
        if !panel.isVisible {
            configureVariant()
        }
        syncModel()
        presentWindow()
        AccessibilityNotification.Announcement(content.headline).post()
    }

    /// Tracks a system-wide drag; the bar offers itself when the drag nears a notch
    /// and withdraws when it wanders off.
    package func dragMoved(to mouse: NSPoint) {
        if let notch = dropGeometry {
            if DropZonePolicy.withdraws(mouse: mouse, notch: notch, barFrame: panel.frame) {
                withdrawDropTarget()
            } else {
                dropWithdrawTask?.cancel()
            }
            return
        }
        guard !presentation.isAnnotating,
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
            let notch = NotchGeometry(screen: screen),
            DropZonePolicy.offers(mouse: mouse, notch: notch)
        else { return }
        offerDropTarget(on: screen, notch: notch)
    }

    /// The monitor's mouse-up arrives before AppKit delivers the drop to `dropView`,
    /// so a release over the bar must not tear the target down — `completeDrop` is
    /// still coming. The timer only reaps a release that produced no drop.
    package func dragEnded() {
        guard let notch = dropGeometry else { return }
        let mouse = NSEvent.mouseLocation
        if DropZonePolicy.withdraws(mouse: mouse, notch: notch, barFrame: panel.frame) {
            withdrawDropTarget()
            return
        }
        dropWithdrawTask?.cancel()
        dropWithdrawTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.withdrawDropTarget()
        }
    }

    private func offerDropTarget(on screen: NSScreen, notch: NotchGeometry) {
        dropGeometry = notch
        dropPending = false
        dismissTask?.cancel()
        anchorScreen = screen
        model.variant = .notch(gap: notch.notchWidth, height: notch.notchHeight)
        if let container = panel.contentView, dropView.superview == nil {
            dropView.frame = container.bounds
            dropView.autoresizingMask = [.width, .height]
            container.addSubview(dropView)
        }
        withAnimation(reduceMotion ? nil : Theme.spring) {
            model.isDropTarget = true
        }
        presentWindow()
        AccessibilityNotification.Announcement("Drop to capture").post()
    }

    private func withdrawDropTarget() {
        guard dropGeometry != nil else { return }
        dropWithdrawTask?.cancel()
        dropGeometry = nil
        dropView.removeFromSuperview()
        if presentation.display != nil {
            withAnimation(reduceMotion ? nil : Theme.spring) {
                model.isDropTarget = false
                model.isDropHovered = false
            }
            syncModel()
            layout(animated: true)
            apply(presentation.hoverChanged(false))
        } else {
            // The drop face rides the exit animation; `hideWindow` resets it.
            hideWindow()
        }
    }

    private func completeDrop(_ items: [DroppedItem]) {
        guard dropGeometry != nil else { return }
        dropWithdrawTask?.cancel()
        dropGeometry = nil
        dropView.removeFromSuperview()
        dropPending = true
        performDrop?(items)
    }

    private func dropHoverChanged(_ hovered: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            model.isDropHovered = hovered
        }
    }

    /// Picked once per appearance so the bar doesn't jump forms mid-display: the
    /// notch wrap on a notched screen, the menu-bar pill everywhere else.
    private func configureVariant() {
        let screen = screenUnderMouse()
        anchorScreen = screen
        if let screen, let notch = NotchGeometry(screen: screen) {
            model.variant = .notch(gap: notch.notchWidth, height: notch.notchHeight)
        } else {
            model.variant = .pill
        }
    }

    package func beginAnnotation() {
        // A hotkey landing mid-drag must not open the drawer under the drop face.
        guard dropGeometry == nil, presentation.beginAnnotation() else { return }
        dismissTask?.cancel()
        model.note = model.content?.note ?? ""
        withAnimation(reduceMotion ? nil : Theme.spring) {
            model.isAnnotating = true
        }
        layout(animated: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func saveNoteAndDismiss() {
        if let content = model.content, let id = content.captureID,
            let note = content.noteEdit(from: model.note)
        {
            saveNote(id, note)
        }
        requestDismiss()
    }

    private func requestDismiss() {
        guard dropGeometry == nil else { return }
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
            model.isDropTarget = false
            model.isDropHovered = false
            dropPending = false
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

@MainActor
private func previewModel(
    variant: HUDModel.Variant,
    content: HUDContent = HUDContent(
        style: .captured, captureID: 1, headline: "Captured", detail: "example.com", kind: .link)
) -> HUDModel {
    let model = HUDModel()
    model.variant = variant
    model.content = content
    return model
}

#Preview("Pill") {
    CaptureHUDView(
        model: previewModel(variant: .pill),
        beginAnnotation: {}, saveNote: {}, dismiss: {}, hoverChanged: { _ in })
}

#Preview("Notch") {
    CaptureHUDView(
        model: previewModel(variant: .notch(gap: 180, height: 38)),
        beginAnnotation: {}, saveNote: {}, dismiss: {}, hoverChanged: { _ in })
}

#Preview("Copied") {
    CaptureHUDView(
        model: previewModel(
            variant: .notch(gap: 180, height: 38),
            content: HUDContent(
                style: .copied,
                headline: "Copied to clipboard",
                detail: "Swift Testing — Apple Developer",
                kind: .link,
                host: "developer.apple.com")),
        beginAnnotation: {}, saveNote: {}, dismiss: {}, hoverChanged: { _ in })
}
