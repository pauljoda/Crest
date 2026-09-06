import SwiftUI

struct BrowserFolderAppearanceSettingsSection: View {
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false
    @AppStorage(BrowserFolderAppearancePreference.showsTabCountsKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsTabCounts = true
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = true

    var body: some View {
        Section("Folders") {
            Toggle("Always show folder highlights", isOn: $alwaysVisible)
                .accessibilityIdentifier("folder-always-show-highlights")
            Toggle("Show folder tab counts", isOn: $showsTabCounts)
                .accessibilityIdentifier("folder-show-tab-counts")
            Toggle("Show folder color borders", isOn: $showsBorders)
                .accessibilityIdentifier("folder-show-color-borders")
            CrestFormFootnote("Applies to folders in every Space. Adjust color intensity in each Space's settings.")
            BrowserSpaceFolderAppearancePreview(followsHighlightPreference: true)
        }
    }
}
