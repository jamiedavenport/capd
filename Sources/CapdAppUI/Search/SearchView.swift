import CapdKit
import KeyboardShortcuts
import SwiftUI

/// The Spotlight-shaped card: query field, dense result rows, one-line status bar.
///
/// The window keeps a fixed footprint while results change underneath it, which is what
/// lets every keystroke repaint without the panel itself moving or resizing.
struct SearchView: View {
    @Bindable var model: SearchModel

    @FocusState private var searchFieldFocused: Bool
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !model.availableTags.isEmpty {
                tagBar
            }
            hairline
            results
            hairline
            statusBar
        }
        .frame(width: 640, height: 470)
        .background(Theme.background, in: PanelStyle.shape)
        .overlay(PanelStyle.shape.strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(PanelStyle.shape)
        .background {
            // A key equivalent, so the chord never reaches the field editor during
            // keyDown; plain ⌘⌫ is left to it as delete-to-start-of-line.
            Button(action: model.deleteSelected) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }

    private var searchBar: some View {
        TextField(
            "Search", text: $model.queryText,
            prompt: Text("Search captures…").foregroundStyle(Theme.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(Theme.text)
        .tint(Theme.text)
        .focused($searchFieldFocused)
        .onSubmit { model.openSelected() }
        .onKeyPress(action: handleKey)
        .onExitCommand { model.dismiss() }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .onChange(of: model.focusToken, initial: true) {
            searchFieldFocused = true
        }
    }

    private var tagBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.availableTags, id: \.self) { tag in
                        Button {
                            model.toggleTag(tag)
                        } label: {
                            TagChip(tag: tag, isActive: tag == model.activeTag)
                        }
                        .buttonStyle(.plain)
                        .id(tag)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .animation(reduceMotion ? nil : Theme.quickSpring, value: model.activeTag)
            }
            .onChange(of: model.activeTag) {
                guard let tag = model.activeTag else { return }
                withAnimation(reduceMotion ? nil : Theme.quickSpring) {
                    proxy.scrollTo(tag)
                }
            }
        }
    }

    /// Arrows and the command chords are steered here while the field keeps focus, so
    /// navigating never means leaving the keyboard or the query. Tab is claimed before
    /// AppKit spends it on focus traversal — the field is the only focusable thing here.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if let forward = Self.tagCycleForward(for: press.key, modifiers: press.modifiers) {
            model.cycleTag(forward: forward)
            return .handled
        }

        switch press.key {
        case .upArrow:
            model.moveSelection(by: -1)
            return .handled
        case .downArrow:
            model.moveSelection(by: 1)
            return .handled
        case .return where press.modifiers.contains(.command):
            model.copySelected()
            return .handled
        default:
            return .ignored
        }
    }

    /// AppKit may represent Shift-Tab as either Tab plus the Shift modifier or as the
    /// legacy Backtab control character. Accept both forms so the field editor cannot
    /// turn reverse tag navigation into focus traversal.
    static func tagCycleForward(
        for key: KeyEquivalent, modifiers: EventModifiers
    ) -> Bool? {
        if key == .tab {
            return !modifiers.contains(.shift)
        }
        if key == KeyEquivalent(Character("\u{19}")) {
            return false
        }
        return nil
    }

    @ViewBuilder private var results: some View {
        if !model.hasLoaded {
            Color.clear
        } else if model.hits.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let now = Date()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.hits.indices, id: \.self) { index in
                            SearchResultRow(
                                content: SearchRowContent(model.hits[index], now: now),
                                isSelected: index == model.selectedIndex,
                                activeTag: model.activeTag,
                                namespace: selectionNamespace
                            )
                            .id(index)
                            .onTapGesture {
                                model.select(index)
                                model.openSelected()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .animation(Theme.quickSpring, value: model.selectedIndex)
                }
                .onChange(of: model.selectedIndex) {
                    proxy.scrollTo(model.selectedIndex)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.totalCount == 0 ? "bookmark" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            if model.totalCount == 0 {
                Text("Nothing yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Press \(captureShortcut) anywhere to capture what you're looking at.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No matches")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Try fewer words, or drop a site:, tag:, or after: filter.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .transition(.opacity)
    }

    private var captureShortcut: String {
        KeyboardShortcuts.getShortcut(for: .capture).map { "\($0)" } ?? "⌃⌥C"
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(model.hits.count.formatted()) of \(model.totalCount.formatted()) captures")
                .font(Theme.mono(10, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: model.hits.count)
            Spacer()
            if !model.availableTags.isEmpty {
                ShortcutHint(label: "Tags", keys: ["⇥"])
                statusDivider
            }
            ShortcutHint(label: "Open", keys: ["↩"])
            statusDivider
            ShortcutHint(label: "Copy URL", keys: ["⌘", "↩"])
            statusDivider
            ShortcutHint(label: "Delete", keys: ["⌘", "⇧", "⌫"])
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 12)
    }
}

private struct SearchResultRow: View {
    let content: SearchRowContent
    let isSelected: Bool
    let activeTag: String?
    let namespace: Namespace.ID

    @State private var isHovered = false

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 10) {
            FaviconTile(host: content.host, fallbackSymbol: symbol, fallbackTint: tint, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(content.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(Theme.mono(10, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                if let snippet = content.snippet {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            ForEach(content.tags, id: \.self) { tag in
                TagChip(tag: tag, isActive: tag == activeTag)
            }
            Text(content.age)
                .font(Theme.mono(10, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(rowShape)
        .background {
            if isSelected {
                rowShape
                    .fill(Theme.selection)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            } else if isHovered {
                rowShape.fill(Theme.raised)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var symbol: String {
        switch content.kind {
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        }
    }

    private var tint: Color {
        switch content.kind {
        case .link: .blue
        case .text: .orange
        case .image: .purple
        }
    }
}
