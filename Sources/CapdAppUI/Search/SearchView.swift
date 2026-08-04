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
            if !model.isAnswerMode && !model.availableTags.isEmpty {
                tagBar
            }
            hairline
            content
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
            prompt: Text("Search captures or ask a question…").foregroundStyle(Theme.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(Theme.text)
        .tint(Theme.text)
        .focused($searchFieldFocused)
        .onSubmit { model.submit() }
        .onKeyPress(action: handleKey)
        .onExitCommand { model.handleEscape() }
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
        if model.isAnswerMode {
            if press.key == .return, press.modifiers.contains(.command), model.libraryAnswer != nil
            {
                model.copyAnswer()
                return .handled
            }
            return .ignored
        }

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

    @ViewBuilder private var content: some View {
        if model.isAnswering {
            answerLoading
        } else if let answer = model.libraryAnswer {
            answerView(answer)
        } else if let error = model.answerError {
            answerFailure(error)
        } else {
            searchContent
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            if showsAvailabilityNudge {
                availabilityNudge
                hairline
            }
            results
        }
    }

    private var showsAvailabilityNudge: Bool {
        guard model.hasQuestion, model.explicitlyAsking else { return false }
        if case .unavailable = model.answerAvailability { return true }
        return false
    }

    @ViewBuilder private var availabilityNudge: some View {
        if case .unavailable(let reason) = model.answerAvailability {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Cap needs Apple Intelligence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(reason.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if reason == .appleIntelligenceOff {
                    Button("Open Settings", action: model.openIntelligenceSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var results: some View {
        if !model.hasLoaded {
            Color.clear
        } else if model.hits.isEmpty && !model.showsAskOption {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let now = Date()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if model.showsAskOption {
                            AskCapResultRow(
                                isSelected: model.isAskSelected,
                                hasQuestion: model.hasQuestion,
                                namespace: selectionNamespace
                            )
                            .id(0)
                            .onTapGesture {
                                model.selectAskCap()
                                model.submit()
                            }
                        }
                        ForEach(model.hits.indices, id: \.self) { index in
                            SearchResultRow(
                                content: SearchRowContent(model.hits[index], now: now),
                                isSelected: model.isCaptureSelected(index),
                                activeTag: model.activeTag,
                                namespace: selectionNamespace
                            )
                            .id(index + (model.showsAskOption ? 1 : 0))
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

    private var answerLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            VStack(spacing: 4) {
                Text("Reading your captures")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Finding the strongest matches and checking every claim.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func answerFailure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: 4) {
                Text("Couldn't answer that")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: 14) {
                Button("Try again", action: model.askCap)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Button("Show search results", action: model.clearAnswer)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func answerView(_ answer: LibraryAnswer) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text("Answer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.bottom, 14)

                ForEach(answer.passages) { passage in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(passage.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 5) {
                            ForEach(passage.citations, id: \.self) { number in
                                citationButton(number)
                            }
                        }
                    }
                    .padding(.bottom, 14)
                }

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.vertical, 2)

                Text("Sources")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 10)

                ForEach(answer.sources) { source in
                    Button {
                        model.openAnswerSource(source.number)
                    } label: {
                        HStack(spacing: 9) {
                            FaviconTile(
                                host: source.host,
                                fallbackSymbol: sourceSymbol(source.kind),
                                fallbackTint: sourceTint(source.kind),
                                size: 20)
                            Text("[\(source.number)]")
                                .font(Theme.mono(10, weight: .regular))
                                .foregroundStyle(Theme.textTertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                if let location = source.host ?? source.url {
                                    Text(location)
                                        .font(Theme.mono(9.5, weight: .regular))
                                        .foregroundStyle(Theme.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func citationButton(_ number: Int) -> some View {
        Button {
            model.openAnswerSource(number)
        } label: {
            Text("[\(number)]")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open source \(number)")
    }

    private func sourceSymbol(_ kind: CaptureKind) -> String {
        switch kind {
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        }
    }

    private func sourceTint(_ kind: CaptureKind) -> Color {
        switch kind {
        case .link: .blue
        case .text: .orange
        case .image: .purple
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
            if let answer = model.libraryAnswer {
                Text("\(answer.sources.count.formatted()) sources")
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            } else if model.isAnswering {
                Text("Answering on device")
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            } else if model.answerError != nil {
                Text("Answer unavailable")
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("\(model.hits.count.formatted()) of \(model.totalCount.formatted()) captures")
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: model.hits.count)
            }
            Spacer()
            if model.libraryAnswer != nil {
                ShortcutHint(label: "Back", keys: ["esc"])
                statusDivider
                ShortcutHint(label: "Copy answer", keys: ["⌘", "↩"])
            } else if model.isAnswerMode {
                ShortcutHint(label: "Back", keys: ["esc"])
            } else {
                if !model.availableTags.isEmpty {
                    ShortcutHint(label: "Tags", keys: ["⇥"])
                    statusDivider
                }
                if model.isAskSelected {
                    if model.hasQuestion {
                        ShortcutHint(label: "Ask", keys: ["↩"])
                    } else {
                        Text("Type a question to ask")
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    ShortcutHint(label: "Open", keys: ["↩"])
                    statusDivider
                    ShortcutHint(label: "Copy URL", keys: ["⌘", "↩"])
                    statusDivider
                    ShortcutHint(label: "Delete", keys: ["⌘", "⇧", "⌫"])
                }
            }
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

private struct AskCapResultRow: View {
    let isSelected: Bool
    let hasQuestion: Bool
    let namespace: Namespace.ID

    @State private var isHovered = false

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Cap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(
                    hasQuestion
                        ? "Answer from the best matches, with citations."
                        : "Type a question to ask your library."
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            if isSelected && hasQuestion {
                Text("↩")
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
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
