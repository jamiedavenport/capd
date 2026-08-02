import KeyboardShortcuts
import SwiftUI

extension Browser {
    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .firefox: "Firefox"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.step.title)
                    .font(.title2.bold())
                Text(model.step.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 540, height: 400)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.conflicted.contains(name) {
                Label(
                    "Taken by a macOS system shortcut — record another combination.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.axTrusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var browsers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.runningBrowsers.isEmpty {
                Text(
                    "No supported browser is running. That's fine — macOS will ask "
                        + "the first time you capture from one."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(model.runningBrowsers, id: \.self) { browser in
                    browserRow(browser)
                }
            }
        }
    }

    private func browserRow(_ browser: Browser) -> some View {
        HStack {
            Text(browser.displayName)
            Spacer()
            switch model.consents[browser] {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Declined", systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
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
            guidedRow(
                done: model.hasCaptured,
                text: "Press \(model.captureShortcut ?? "the capture hotkey") in any app "
                    + "to save your first capture.")
            guidedRow(
                done: model.hasSearched,
                text: "Press \(model.searchShortcut ?? "the search hotkey") and type a "
                    + "word from it.")
            Spacer()
            Label(
                model.agentLoaded
                    ? "Background enrichment agent installed."
                    : "Background enrichment agent not running yet — `cap doctor` can repair it.",
                systemImage: model.agentLoaded ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func guidedRow(done: Bool, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            if model.step != .hotkeys {
                Button("Back") {
                    model.back()
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
                    model.advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
