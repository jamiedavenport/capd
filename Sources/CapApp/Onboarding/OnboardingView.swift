import KeyboardShortcuts
import SwiftUI

extension Browser {
    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .firefox: "Firefox"
        case .zen: "Zen"
        case .librewolf: "LibreWolf"
        case .waterfox: "Waterfox"
        }
    }
}

extension OnboardingStep {
    fileprivate var title: String {
        switch self {
        case .hotkeys: "Two hotkeys"
        case .accessibility: "Accessibility access"
        case .browsers: "Browser access"
        case .firstCapture: "Try it"
        }
    }

    fileprivate var subtitle: String {
        switch self {
        case .hotkeys:
            "cap lives behind two global hotkeys. Change either one here if it clashes "
                + "with something you already use."
        case .accessibility:
            "Reading the text you've selected needs macOS Accessibility access."
        case .browsers:
            "cap asks the frontmost browser for its current tab. macOS shows one consent "
                + "dialog per browser — approving now keeps your first capture uninterrupted."
        case .firstCapture:
            "That's the whole loop: capture anything, find it again in seconds."
        }
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    @State private var direction: Edge = .trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.step.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(model.step.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id("header-\(model.step.rawValue)")
                .transition(.opacity)
                Spacer(minLength: 16)
                stepDots
            }
            .padding(24)

            ZStack(alignment: .topLeading) {
                content
                    .id(model.step)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: direction).combined(with: .opacity),
                            removal: .move(edge: direction == .trailing ? .leading : .trailing)
                                .combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .clipped()

            hairline
            footer
                .padding(16)
        }
        .frame(width: 540, height: 400)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var stepDots: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(dotColor(for: step))
                    .frame(width: step == model.step ? 16 : 5, height: 5)
            }
        }
        .padding(.top, 5)
    }

    private func dotColor(for step: OnboardingStep) -> Color {
        if step == model.step { return Theme.text }
        return step.rawValue < model.step.rawValue ? Theme.textSecondary : Theme.raised
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .hotkeys:
            hotkeys
        case .accessibility:
            accessibility
        case .browsers:
            browsers
        case .firstCapture:
            firstCapture
        }
    }

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 16) {
            hotkeyRow(
                name: .capture,
                label: "Capture:",
                hint: "Saves the page, selection, or image in front of you.")
            hotkeyRow(
                name: .search,
                label: "Search:",
                hint: "Opens the search window from anywhere.")
        }
    }

    private func hotkeyRow(
        name: KeyboardShortcuts.Name, label: String, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KeyboardShortcuts.Recorder(label, name: name)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            if model.conflicted.contains(name) {
                Label(
                    "Taken by a macOS system shortcut — record another combination.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.conflicted)
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.axTrusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            } else {
                HStack(spacing: 12) {
                    Button("Grant Accessibility Access…") {
                        model.requestAccessibility()
                    }
                    Button("Open System Settings") {
                        model.openAccessibilitySettings()
                    }
                }
                Text(
                    "If you skip this, cap is clipboard-only: capture saves what you've "
                        + "already copied, and can't read the text you've selected."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Theme.spring, value: model.axTrusted)
    }

    private var browsers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.runningBrowsers.isEmpty {
                Text(
                    "No supported browser is running. That's fine — macOS will ask "
                        + "the first time you capture from one."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.runningBrowsers, id: \.self) { browser in
                    browserRow(browser)
                }
            }
        }
        .animation(Theme.quickSpring, value: model.consents)
    }

    private func browserRow(_ browser: Browser) -> some View {
        HStack {
            Text(browser.displayName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            Spacer()
            switch model.consents[browser] {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .denied:
                Label("Declined", systemImage: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                Button("Open System Settings") {
                    model.openAutomationSettings()
                }
            default:
                if model.pendingConsents[browser] != nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Allow…") {
                        model.requestConsent(for: browser)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var firstCapture: some View {
        VStack(alignment: .leading, spacing: 14) {
            guidedRow(done: model.hasCaptured) {
                Text("Press")
                Keycap(label: model.captureShortcut ?? "⌃⌥C")
                Text("in any app to save your first capture.")
            }
            guidedRow(done: model.hasSearched) {
                Text("Press")
                Keycap(label: model.searchShortcut ?? "⌥⇧Space")
                Text("and type a word from it.")
            }
            Spacer()
            Label(
                model.agentLoaded
                    ? "Background enrichment agent installed."
                    : "Background enrichment agent not running yet — `cap doctor` can repair it.",
                systemImage: model.agentLoaded ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func guidedRow(done: Bool, @ViewBuilder text: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                .contentTransition(.symbolEffect(.replace))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                text()
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
        }
        .animation(Theme.spring, value: done)
    }

    private var footer: some View {
        HStack {
            if model.step != .hotkeys {
                Button("Back") {
                    go(.back)
                }
            }
            Spacer()
            if model.isLastStep {
                Button("Finish") {
                    model.finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") {
                    go(.forward)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private enum Move {
        case forward, back
    }

    private func go(_ move: Move) {
        direction = move == .forward ? .trailing : .leading
        withAnimation(Theme.spring) {
            switch move {
            case .forward: model.advance()
            case .back: model.back()
            }
        }
    }
}
