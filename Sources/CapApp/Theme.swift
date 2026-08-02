import SwiftUI

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

/// Footer action hint: a label followed by keycap chips, e.g. "Open ↩".
struct ShortcutHint: View {
    var label: String
    var keys: [String]

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 1)
                        .background(
                            .quaternary,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }
}
