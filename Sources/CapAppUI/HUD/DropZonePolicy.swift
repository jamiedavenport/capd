import AppKit

/// The notch's shape and position in global screen coordinates.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
}

extension NotchGeometry {
    /// nil on screens without a notch.
    init?(screen: NSScreen) {
        guard screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        else { return nil }
        self.init(
            screenFrame: screen.frame,
            notchWidth: screen.frame.width - left.width - right.width,
            notchHeight: screen.safeAreaInsets.top)
    }
}

/// When a global drag turns the notch HUD into a drop target, and when the offer is
/// withdrawn. Pure so the thresholds test without screens or live drags.
enum DropZonePolicy {
    /// How far past the notch's sides a drag still counts as heading for it.
    static let horizontalMargin: CGFloat = 80
    /// How far below the top edge the offer starts.
    static let approachDepth: CGFloat = 100
    /// Grace band around the offered bar so skimming its edge doesn't flicker it away.
    static let exitMargin: CGFloat = 40

    static func offers(mouse: CGPoint, notch: NotchGeometry) -> Bool {
        approachZone(for: notch).contains(mouse)
    }

    /// The bar is wider than the approach zone, so the offer holds over either.
    static func withdraws(mouse: CGPoint, notch: NotchGeometry, barFrame: CGRect) -> Bool {
        !approachZone(for: notch).contains(mouse)
            && !barFrame.insetBy(dx: -exitMargin, dy: -exitMargin).contains(mouse)
    }

    private static func approachZone(for notch: NotchGeometry) -> CGRect {
        // Overshoots the top edge by a point: the cursor pinned there reports
        // y == maxY, which `contains` would otherwise exclude.
        CGRect(
            x: notch.screenFrame.midX - notch.notchWidth / 2 - horizontalMargin,
            y: notch.screenFrame.maxY - approachDepth,
            width: notch.notchWidth + 2 * horizontalMargin,
            height: approachDepth + 1)
    }
}
