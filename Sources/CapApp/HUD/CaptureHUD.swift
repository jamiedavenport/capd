import AppKit
import SwiftUI

@MainActor
@Observable
final class HUDModel {
    var content: HUDContent?
    var isAnnotating = false
    var note = ""
}

struct CaptureHUDView: View {
    @Bindable var model: HUDModel
    var beginAnnotation: () -> Void
    var saveNote: () -> Void
    var dismiss: () -> Void

    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.content?.headline ?? "")
                        .font(.headline)
                    if let detail = model.content?.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if model.content?.canAnnotate == true, !model.isAnnotating {
                        Text("Click to add a note")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        .frame(minWidth: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if model.content?.canAnnotate == true, !model.isAnnotating {
                beginAnnotation()
            }
        }
        .onExitCommand(perform: dismiss)
    }

    private var symbol: String {
        switch model.content?.style {
        case .captured, .none: "checkmark.circle.fill"
        case .duplicate: "clock.arrow.circlepath"
        case .blocked: "lock.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch model.content?.style {
        case .captured, .none: .green
        case .duplicate: .secondary
        case .blocked, .failed: .orange
        }
    }
}

/// Borderless so the toast draws its own shape; key-capable so ⏎ and esc reach the
/// note field without activating the app.
private final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns the toast window: shows a capture outcome near the menu bar, auto-dismisses,
/// and turns a click into the annotation flow.
@MainActor
final class HUDPanelController {
    private let model = HUDModel()
    private let saveNote: (Int64, String) -> Void
    private let panel: HUDPanel
    private var hosting: NSHostingView<CaptureHUDView>!
    private var dismissTask: Task<Void, Never>?

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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        hosting = NSHostingView(
            rootView: CaptureHUDView(
                model: model,
                beginAnnotation: { [weak self] in self?.beginAnnotation() },
                saveNote: { [weak self] in self?.saveNoteAndDismiss() },
                dismiss: { [weak self] in self?.dismiss() }))
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.dismiss() }
    }

    func show(_ content: HUDContent) {
        model.content = content
        model.isAnnotating = false
        model.note = ""
        layout()
        panel.orderFrontRegardless()
        scheduleDismiss()
    }

    private func beginAnnotation() {
        dismissTask?.cancel()
        model.isAnnotating = true
        layout()
        panel.makeKeyAndOrderFront(nil)
    }

    private func saveNoteAndDismiss() {
        if let id = model.content?.captureID {
            let note = model.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                saveNote(id, note)
            }
        }
        dismiss()
    }

    private func dismiss() {
        dismissTask?.cancel()
        panel.orderOut(nil)
        model.content = nil
        model.isAnnotating = false
        model.note = ""
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func layout() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16))
    }
}
