import CapdKit
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
        case .overview: "Meet Capd"
        case .hotkeys: "Choose your shortcuts"
        case .permissions: "Connect your Mac"
        case .firstCapture: "Make it yours"
        }
    }

    fileprivate var subtitle: String {
        switch self {
        case .overview:
            "Capture what matters without leaving your flow, then find it again in seconds."
        case .hotkeys:
            "Capd stays out of the way until you call it. Change any shortcut that clashes."
        case .permissions:
            "These optional connections make capture effortless. Your library always stays on this Mac."
        case .firstCapture:
            "Complete the loop with something useful from the app you are already using."
        }
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var direction: Edge = .trailing
    @State private var introPhase = IntroPhase.identity
    @State private var showsSetup = false

    var body: some View {
        ZStack {
            AmbientBackdrop(isExpanded: introPhase != .identity && !reduceMotion)

            if showsSetup {
                setup
                    .transition(setupTransition)
            } else {
                cinematicIntro
                    .transition(.opacity)
            }
        }
        .frame(width: 760, height: 520)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .task {
            await playIntro()
        }
        .onExitCommand {
            model.deferSetup()
        }
    }

    private var setupTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(scale: 1.02).combined(with: .opacity)
    }

    private var cinematicIntro: some View {
        ZStack {
            Group {
                switch introPhase {
                case .identity:
                    IdentityMoment()
                case .capture:
                    CaptureMoment()
                case .search:
                    SearchMoment()
                case .promise:
                    PromiseMoment()
                }
            }
            .id(introPhase)
            .transition(
                reduceMotion
                    ? .opacity
                    : .scale(scale: 0.96).combined(with: .opacity))

            VStack {
                Spacer()
                HStack {
                    Text("Private · Native · Yours")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    Spacer()
                    Button("Skip intro") {
                        enterSetup()
                    }
                    .buttonStyle(OnboardingGhostButtonStyle())
                }
                .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Introduction to Capd")
    }

    private var setup: some View {
        VStack(spacing: 0) {
            setupHeader

            ZStack(alignment: .topLeading) {
                chapter
                    .id(model.step)
                    .transition(chapterTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 30)
            .clipped()

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            setupFooter
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 10) {
            CapdMark(size: 23)
            Text("Capd")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Capsule()
                        .fill(dotColor(for: step))
                        .frame(width: step == model.step ? 22 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count), \(model.step.title)"
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
    }

    private func dotColor(for step: OnboardingStep) -> Color {
        if step == model.step { return Theme.accent }
        return step.rawValue < model.step.rawValue ? Theme.textSecondary : Theme.raised
    }

    private var chapterTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: direction == .trailing ? .leading : .trailing)
                .combined(with: .opacity))
    }

    private var chapter: some View {
        VStack(alignment: .leading, spacing: 22) {
            ChapterHeading(title: model.step.title, subtitle: model.step.subtitle)

            Group {
                switch model.step {
                case .overview:
                    overview
                case .hotkeys:
                    hotkeys
                case .permissions:
                    permissions
                case .firstCapture:
                    firstCapture
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var overview: some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(alignment: .leading, spacing: 18) {
                capability(
                    symbol: "bolt.fill",
                    title: "Capture in place",
                    detail: "Save a page, selection, link, note, or image without changing apps.")
                capability(
                    symbol: "text.magnifyingglass",
                    title: "Search the contents",
                    detail: "Find titles, article text, notes, and words recognized inside images.")
                capability(
                    symbol: "lock.fill",
                    title: "Keep it private",
                    detail: "No account, telemetry, subscription, or cloud library.")
            }
            .frame(width: 310, alignment: .leading)

            CaptureLibraryPreview()
                .frame(maxWidth: .infinity)
        }
    }

    private func capability(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeys: some View {
        VStack(spacing: 9) {
            hotkeyRow(
                name: .capture,
                symbol: "plus.circle",
                title: "Capture",
                hint: "Save the page, selection, or image in front of you.")
            hotkeyRow(
                name: .annotate,
                symbol: "square.and.pencil",
                title: "Add a note",
                hint: "Attach context while the capture confirmation is visible.")
            hotkeyRow(
                name: .search,
                symbol: "magnifyingglass",
                title: "Search",
                hint: "Open your library from anywhere on your Mac.")
        }
    }

    private func hotkeyRow(
        name: KeyboardShortcuts.Name,
        symbol: String,
        title: String,
        hint: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                if model.conflicted.contains(name) {
                    Label(
                        "Already used by macOS. Record another combination.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
                }
            }

            Spacer(minLength: 12)

            KeyboardShortcuts.Recorder("", name: name)
                .labelsHidden()
                .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: model.conflicted)
    }

    private var permissions: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                accessibilityTile
                shareSheetTile
            }
            VStack(spacing: 12) {
                browsersTile
                intelligenceTile
            }
        }
    }

    private var accessibilityTile: some View {
        permissionTile(
            title: "Selected text",
            symbol: "accessibility",
            status: model.axTrusted ? "Connected" : "Optional",
            statusColor: model.axTrusted ? Theme.success : Theme.textTertiary
        ) {
            if model.axTrusted {
                permissionReady("Accessibility access granted.")
            } else {
                HStack(spacing: 8) {
                    Button("Allow…") { model.requestAccessibility() }
                    Button("Settings") { model.openAccessibilitySettings() }
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var shareSheetTile: some View {
        permissionTile(
            title: "Share Sheet",
            symbol: "square.and.arrow.up",
            status: model.shareStatus == .enabled ? "Connected" : "Optional",
            statusColor: model.shareStatus == .enabled ? Theme.success : Theme.textTertiary
        ) {
            switch model.shareStatus {
            case .enabled:
                permissionReady("Available from apps that share links.")
            case .disabled, .defaulted:
                Button("Add Capd") { model.enableShareExtension() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            case .unregistered:
                Text("Appears automatically after macOS registers the extension.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .animation(Theme.spring, value: model.shareStatus)
    }

    private var browsersTile: some View {
        permissionTile(
            title: "Browser tabs",
            symbol: "safari",
            status: browserStatus,
            statusColor: browserStatusColor
        ) {
            if model.runningBrowsers.isEmpty {
                Text("Capd will ask when you first capture from a supported browser.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 5) {
                    ForEach(model.runningBrowsers.prefix(3), id: \.self) { browser in
                        browserRow(browser)
                    }
                }
            }
        }
        .animation(Theme.quickSpring, value: model.consents)
    }

    private var browserStatus: String {
        if model.runningBrowsers.isEmpty { return "On first use" }
        if model.runningBrowsers.allSatisfy({ model.consents[$0] == .granted }) {
            return "Connected"
        }
        return "Optional"
    }

    private var browserStatusColor: Color {
        browserStatus == "Connected" ? Theme.success : Theme.textTertiary
    }

    private func browserRow(_ browser: Browser) -> some View {
        HStack(spacing: 6) {
            Text(browser.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            switch model.consents[browser] {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            case .denied:
                Button("Settings") { model.openAutomationSettings() }
                    .buttonStyle(OnboardingCompactButtonStyle())
            default:
                if model.pendingConsents[browser] != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Allow…") { model.requestConsent(for: browser) }
                        .buttonStyle(OnboardingCompactButtonStyle())
                }
            }
        }
        .font(.system(size: 10.5))
    }

    private var intelligenceTile: some View {
        permissionTile(
            title: "On-device tagging",
            symbol: "sparkles",
            status: intelligenceStatus,
            statusColor: intelligenceStatusColor
        ) {
            switch model.taggerAvailability {
            case .available:
                permissionReady("Apple Intelligence is ready.")
            case .unavailable(.appleIntelligenceOff):
                Button("Open Settings") { model.openIntelligenceSettings() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            case .unavailable(.modelDownloading):
                Text("The model is downloading. Tagging starts automatically.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            case .unavailable(.deviceNotEligible):
                Text("Everything works normally without automatic tags.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            case .unavailable(.unknown):
                Text("Tagging starts automatically when the model is available.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .animation(Theme.spring, value: model.taggerAvailability)
    }

    private var intelligenceStatus: String {
        switch model.taggerAvailability {
        case .available: "Ready"
        case .unavailable(.modelDownloading): "Downloading"
        case .unavailable(.deviceNotEligible): "Unavailable"
        case .unavailable: "Optional"
        }
    }

    private var intelligenceStatusColor: Color {
        model.taggerAvailability == .available ? Theme.success : Theme.textTertiary
    }

    private func permissionTile<Content: View>(
        title: String,
        symbol: String,
        status: String,
        statusColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(status)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private func permissionReady(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textSecondary)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Theme.success, Theme.success)
    }

    private var firstCapture: some View {
        HStack(spacing: 14) {
            GuidedAction(
                number: "01",
                title: "Capture something useful",
                detail: "From any app, save the page, selection, link, or image in front of you.",
                shortcut: model.captureShortcut ?? "⌃⌥C",
                done: model.hasCaptured)

            GuidedAction(
                number: "02",
                title: "Find it again",
                detail: "Open Capd and search for a word you remember from the capture.",
                shortcut: model.searchShortcut ?? "⌥⇧Space",
                done: model.hasSearched)
        }
        .overlay(alignment: .bottomLeading) {
            Label(
                model.agentLoaded
                    ? "Background enrichment is running."
                    : "Background enrichment is starting. `capd doctor` can repair it if needed.",
                systemImage: model.agentLoaded ? "checkmark.circle" : "clock"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textTertiary)
            .offset(y: 28)
        }
    }

    private var setupFooter: some View {
        HStack(spacing: 12) {
            Button("Set up later") {
                model.deferSetup()
            }
            .buttonStyle(OnboardingGhostButtonStyle())

            Spacer()

            if model.step != .overview {
                Button("Back") {
                    go(.back)
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            Button(model.isLastStep ? "Finish" : "Continue") {
                if model.isLastStep {
                    model.finish()
                } else {
                    go(.forward)
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .frame(height: 66)
    }

    private enum Move {
        case forward
        case back
    }

    private func go(_ move: Move) {
        direction = move == .forward ? .trailing : .leading
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring) {
            switch move {
            case .forward: model.advance()
            case .back: model.back()
            }
        }
    }

    @MainActor
    private func playIntro() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(350))
            enterSetup()
            return
        }

        let sequence: [(IntroPhase, Duration)] = [
            (.capture, .milliseconds(1250)),
            (.search, .milliseconds(1700)),
            (.promise, .milliseconds(1700)),
        ]

        for (phase, delay) in sequence {
            try? await Task.sleep(for: delay)
            guard !showsSetup, !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.65)) {
                introPhase = phase
            }
        }

        try? await Task.sleep(for: .milliseconds(1300))
        guard !showsSetup, !Task.isCancelled else { return }
        enterSetup()
    }

    private func enterSetup() {
        guard !showsSetup else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.7)) {
            showsSetup = true
        }
    }
}

private enum IntroPhase: Int {
    case identity
    case capture
    case search
    case promise
}

private struct AmbientBackdrop: View {
    var isExpanded: Bool

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: isExpanded ? 270 : 190, y: isExpanded ? -210 : -260)
            Circle()
                .fill(Theme.accentSecondary.opacity(0.1))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: isExpanded ? -300 : -230, y: isExpanded ? 250 : 290)
        }
        .animation(.easeInOut(duration: 2.4), value: isExpanded)
        .allowsHitTesting(false)
    }
}

private struct IdentityMoment: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            CapdMark(size: 82)
                .scaleEffect(appeared ? 1 : 0.78)
                .opacity(appeared ? 1 : 0)
            Text("Capd")
                .font(.system(size: 42, weight: .semibold))
                .tracking(-1.4)
                .foregroundStyle(Theme.text)
            Text("A private place for what matters.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) {
                appeared = true
            }
        }
    }
}

private struct CaptureMoment: View {
    @State private var collected = false

    var body: some View {
        VStack(spacing: 34) {
            HStack(spacing: 18) {
                ArtifactCard(symbol: "safari", label: "A useful page")
                    .offset(x: collected ? 0 : -70, y: collected ? 0 : 18)
                ArtifactCard(symbol: "text.quote", label: "A selected idea")
                    .offset(y: collected ? 0 : -28)
                ArtifactCard(symbol: "photo", label: "An image")
                    .offset(x: collected ? 0 : 70, y: collected ? 0 : 18)
            }
            .opacity(collected ? 1 : 0)

            HStack(spacing: 10) {
                CapdMark(size: 22)
                Text("Captured")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Keycap(label: "⌃⌥C")
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(width: 300, height: 46)
            .background(Color.black.opacity(0.88), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(collected ? 1 : 0.9)
            .opacity(collected ? 1 : 0)

            Text("Capture without breaking focus")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) {
                collected = true
            }
        }
    }
}

private struct ArtifactCard: View {
    var symbol: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(width: 142, height: 78, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }
}

private struct SearchMoment: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    Text("swift concurrency")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Keycap(label: "⌘1")
                }
                .padding(.horizontal, 16)
                .frame(height: 48)

                Rectangle().fill(Theme.border).frame(height: 1)

                SearchResultPreview(
                    symbol: "safari",
                    title: "Approachable Concurrency in Swift",
                    detail: "Structured tasks, actors, and safe shared state.")
                SearchResultPreview(
                    symbol: "doc.text",
                    title: "Notes on isolation",
                    detail: "The details you saved are searchable too."
                )
                .opacity(0.65)
            }
            .frame(width: 480)
            .background(
                Color.black.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            }
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)

            Text("Search more than bookmarks")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) {
                appeared = true
            }
        }
    }
}

private struct SearchResultPreview: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }
}

private struct PromiseMoment: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            CapdMark(size: 54)
            Text("Save anything. Find it in seconds.")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("No account. No telemetry. Your library stays on your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) {
                appeared = true
            }
        }
    }
}

private struct ChapterHeading: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CaptureLibraryPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textTertiary)
                Text("Search everything you saved")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Rectangle().fill(Theme.border).frame(height: 1)

            libraryRow(symbol: "safari", title: "Designing fluid interfaces", tag: "design")
            libraryRow(symbol: "doc.text", title: "A note worth keeping", tag: "notes")
            libraryRow(symbol: "photo", title: "Whiteboard sketch", tag: "reference")
        }
        .background(
            Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private func libraryRow(symbol: String, title: String, tag: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            TagChip(tag: tag)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

private struct GuidedAction: View {
    var number: String
    var title: String
    var detail: String
    var shortcut: String
    var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(number)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }

            Spacer()

            Text(done ? "Done" : title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            Spacer()

            HStack(spacing: 7) {
                Text(done ? "Completed" : "Press")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                if !done {
                    Keycap(label: shortcut)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(done ? Theme.success.opacity(0.35) : Theme.border, lineWidth: 1)
        }
        .animation(Theme.spring, value: done)
    }
}

private struct CapdMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.text, lineWidth: size * 0.1)
            Circle()
                .fill(Theme.text)
                .frame(width: size * 0.67, height: size * 0.67)
                .offset(y: size * 0.165)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(
                configuration.isPressed ? Theme.accent.opacity(0.78) : Theme.accent,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.textSecondary : Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                configuration.isPressed ? Theme.selection : Theme.raised,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

private struct OnboardingCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Theme.textSecondary : Theme.text)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                configuration.isPressed ? Theme.selection : Theme.raised,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

private struct OnboardingGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
    }
}
