import SwiftUI

/// The Shortcuts row that turns the recent tabs panel on or off, with what a
/// quick jump does without it.
struct RecentTabSwitcherSettingRow: View {
    /// The binding of the Most Recent Tab command, named in the note.
    let shortcut: BrowserShortcut?

    @AppStorage(RecentTabSwitcherPreference.key)
    private var showsRecentTabs = RecentTabSwitcherPreference.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            CrestSettingRow("Show recent tabs while switching") {
                Toggle("Show recent tabs while switching", isOn: $showsRecentTabs).labelsHidden()
            }
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var note: String {
        guard let shortcut else {
            return String(localized: "When off, switching jumps to your last tab without showing previews.")
        }
        return String(localized: "When off, \(shortcut.displayString) jumps to your last tab without showing previews.")
    }
}
