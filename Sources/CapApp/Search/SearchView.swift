import CapKit
import KeyboardShortcuts
import SwiftUI

/// The Spotlight-shaped card: query field, dense result rows, one-line status bar.
///
/// The window keeps a fixed footprint while results change underneath it, which is what
/// lets every keystroke repaint without the panel itself moving or resizing.
struct SearchView: View {
    @Bindable var model: SearchModel

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            results
            Divider()
            statusBar
        }
        .frame(width: 640, height: 470)
        .background(.regularMaterial, in: PanelStyle.shape)
        .contentShape(PanelStyle.shape)
        .background {
            // ⌘⌫ must be a key equivalent: the field editor consumes it as
            // deleteToBeginningOfLine: during keyDown, before onKeyPress sees it.
            Button(action: model.deleteSelected) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: .command)
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var searchBar: some View {
        TextField("Search captures…", text: $model.queryText)
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($searchFieldFocused)
            .onSubmit { model.openSelected() }
            .onKeyPress(action: handleKey)
            .onExitCommand { model.dismiss() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .onChange(of: model.focusToken, initial: true) {
                searchFieldFocused = true
            }
    }

    /// Arrows and the command chords are steered here while the field keeps focus, so
    /// navigating never means leaving the keyboard or the query.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
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
                                isSelected: index == model.selectedIndex
                            )
                            .id(index)
                            .onTapGesture(count: 2) {
                                model.select(index)
                                model.openSelected()
                            }
                            .onTapGesture { model.select(index) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selectedIndex) {
                    proxy.scrollTo(model.selectedIndex)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            if model.totalCount == 0 {
                Text("Nothing yet")
                    .font(.headline)
                Text("Press \(captureShortcut) anywhere to capture what you're looking at.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No matches")
                    .font(.headline)
                Text("Try fewer words, or drop a site: or after: filter.")
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }

    private var captureShortcut: String {
        KeyboardShortcuts.getShortcut(for: .capture).map { "\($0)" } ?? "⌃⌥C"
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(model.hits.count.formatted()) of \(model.totalCount.formatted()) captures")
                .foregroundStyle(.secondary)
            Spacer()
            ShortcutHint(label: "Open", keys: ["↩"])
            statusDivider
            ShortcutHint(label: "Copy URL", keys: ["⌘", "↩"])
            statusDivider
            ShortcutHint(label: "Delete", keys: ["⌘", "⌫"])
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 12)
    }
}

private struct SearchResultRow: View {
    let content: SearchRowContent
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(content.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let snippet = content.snippet {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(content.age)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
