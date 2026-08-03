import KeyboardShortcuts
import SwiftUI

package struct SettingsView: View {
    @Bindable var settings: AppSettings

    package init(settings: AppSettings) {
        self.settings = settings
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Hotkeys") {
                row("Capture") {
                    KeyboardShortcuts.Recorder("", name: .capture)
                }
                hairline
                row("Note last capture") {
                    KeyboardShortcuts.Recorder("", name: .annotate)
                }
                hairline
                row("Search") {
                    KeyboardShortcuts.Recorder("", name: .search)
                }
            }
            section("Network") {
                row("Fetch page content for link captures") {
                    toggle($settings.fetchesPageBodies)
                }
                hairline
                row("Check weekly for a new version") {
                    toggle($settings.checksForUpdates)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.mono(9.5))
                .kerning(1)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 12)
            VStack(spacing: 0) {
                rows()
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding.animation(Theme.quickSpring))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.success)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "dev.jxd.cap.preview")!
    SettingsView(settings: AppSettings(defaults: defaults))
}
