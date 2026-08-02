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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search captures", text: $model.queryText)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFieldFocused)
                .onSubmit { model.openSelected() }
                .onKeyPress(action: handleKey)
                .onExitCommand { model.dismiss() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        case .delete where press.modifiers.contains(.command):
            model.deleteSelected()
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
                    LazyVStack(spacing: 0) {
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
        HStack {
            Text("\(model.hits.count.formatted()) of \(model.totalCount.formatted()) captures")
            Spacer()
            Text("↩ open · ⌘↩ copy url · ⌘⌫ delete")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct SearchResultRow: View {
    let content: SearchRowContent
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(content.badge)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondaryColor)
                .frame(width: 34)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(secondaryColor.opacity(0.5)))
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                if let snippet = content.snippet {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Text(content.age)
                .font(.system(size: 11))
                .foregroundStyle(secondaryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
    }

    private var primaryColor: Color {
        isSelected ? .white : .primary
    }

    private var secondaryColor: Color {
        isSelected ? .white.opacity(0.75) : .secondary
    }
}
