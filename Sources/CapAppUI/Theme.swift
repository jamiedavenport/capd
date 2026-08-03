import SwiftUI

/// cap's fixed design language: near-black surfaces, light small type, mono for
/// machine-ish text (domains, ages, counts, keycaps). Surfaces read these tokens
/// instead of system materials so the app looks the same in light and dark mode.
enum Theme {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let raised = Color.white.opacity(0.05)
    /// Chip behind dark favicon artwork: bright enough to carry a black glyph,
    /// shy of searing pure white in a near-black UI.
    static let raisedLight = Color.white.opacity(0.9)
    /// Pure black so the capture bar merges with the physical notch.
    static let bar = Color.black
    static let border = Color.white.opacity(0.09)
    static let text = Color.white.opacity(0.93)
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.34)
    static let selection = Color.white.opacity(0.08)
    static let success = Color(red: 0.35, green: 0.84, blue: 0.5)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.26)

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let quickSpring = Animation.spring(response: 0.2, dampingFraction: 0.85)
}

/// Shared visual language for cap's floating panels — the search bar and capture HUD.
enum PanelStyle {
    static let cornerRadius: CGFloat = 12

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// Rounded-square icon tile, the launcher-style stand-in for an app icon.
struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 24
    var bounce = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: size, height: size)
            .background(
                tint.gradient,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// `IconTile`'s footprint with a site's favicon in place of the symbol. Falls back to
/// the symbol tile whenever no favicon is known — no host, store absent, still
/// fetching, or the site has none — so rows never shift while an icon loads.
struct FaviconTile: View {
    var host: String?
    var fallbackSymbol: String
    var fallbackTint: Color
    var size: CGFloat

    @Environment(\.faviconStore) private var favicons

    var body: some View {
        if let host, let favicon = favicons?.favicon(forHost: host) {
            Image(nsImage: favicon.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.09)
                .frame(width: size, height: size)
                .background(
                    favicon.needsLightBacking ? Theme.raisedLight : Theme.raised,
                    in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            IconTile(symbol: fallbackSymbol, tint: fallbackTint, size: size)
        }
    }
}

/// A tag chip: `Keycap`'s materials in a capsule, so tags read as data rather than keys.
struct TagChip: View {
    var tag: String
    var isActive = false

    var body: some View {
        Text(tag)
            .font(Theme.mono(9.5))
            .foregroundStyle(isActive ? Theme.text : Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(isActive ? Theme.selection : Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// A single keyboard-key chip, e.g. `⌘` or `↩`.
struct Keycap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Footer action hint: a label followed by keycap chips, e.g. "Open ↩".
struct ShortcutHint: View {
    var label: String
    var keys: [String]

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Keycap(label: key)
                }
            }
        }
    }
}
