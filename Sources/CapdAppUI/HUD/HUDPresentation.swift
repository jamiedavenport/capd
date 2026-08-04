import Foundation

/// The toast's decision core: what's on screen, when the auto-dismiss clock may run,
/// and what happens to captures that land mid-annotation. Pure so every rule tests
/// without AppKit.
struct HUDPresentation: Equatable {
    struct Display: Equatable {
        var content: HUDContent
        var streak = 1
    }

    enum TimerAction: Equatable {
        case restart(Duration)
        case stop
        case none
    }

    private(set) var display: Display?
    private(set) var isAnnotating = false
    private(set) var isHovering = false
    private(set) var buffered: HUDContent?

    mutating func show(_ content: HUDContent) -> TimerAction {
        // A capture landing mid-annotation must not wipe the note being typed.
        if isAnnotating {
            buffered = content
            return .none
        }
        display = coalesced(content)
        return isHovering ? .stop : .restart(content.style.displayDuration)
    }

    mutating func hoverChanged(_ hovering: Bool) -> TimerAction {
        isHovering = hovering
        guard let display, !isAnnotating else { return .none }
        return hovering ? .stop : .restart(display.content.style.displayDuration)
    }

    mutating func beginAnnotation() -> Bool {
        guard display?.content.canAnnotate == true, !isAnnotating else { return false }
        isAnnotating = true
        return true
    }

    /// Annotation ended without a note: clicked in, typed nothing, clicked away.
    mutating func abandonAnnotation() -> TimerAction {
        guard isAnnotating else { return .none }
        isAnnotating = false
        if let next = buffered {
            buffered = nil
            display = coalesced(next)
        }
        guard let display else { return .stop }
        return isHovering ? .stop : .restart(display.content.style.displayDuration)
    }

    /// Explicit dismiss, note save, or timer expiry. A capture buffered during
    /// annotation takes over instead of hiding, so dismissing one toast never
    /// swallows the outcome of a later press.
    mutating func dismiss() -> TimerAction {
        isAnnotating = false
        if let next = buffered {
            buffered = nil
            display = coalesced(next)
            return isHovering ? .stop : .restart(next.style.displayDuration)
        }
        display = nil
        // The window is going away, and a mouse that leaves while it's hidden sends
        // no exit event — a latched hover would leave the next toast timerless.
        isHovering = false
        return .stop
    }

    private func coalesced(_ content: HUDContent) -> Display {
        if content.style == .captured, let display, display.content.style == .captured {
            return Display(content: content, streak: display.streak + 1)
        }
        return Display(content: content)
    }
}

extension HUDContent.Style {
    /// Failures hold longer than successes: their detail is worth reading.
    var displayDuration: Duration {
        switch self {
        case .captured, .copied: .seconds(3)
        case .duplicate: .seconds(4)
        case .insight: .seconds(6)
        case .blocked, .failed: .seconds(6)
        }
    }
}
