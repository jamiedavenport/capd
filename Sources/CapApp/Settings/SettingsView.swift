import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Capture:", name: .capture)
                KeyboardShortcuts.Recorder("Search:", name: .search)
            }
            Section("Network") {
                Toggle("Fetch page content for link captures", isOn: $settings.fetchesPageBodies)
                Toggle("Check weekly for a new version", isOn: $settings.checksForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
