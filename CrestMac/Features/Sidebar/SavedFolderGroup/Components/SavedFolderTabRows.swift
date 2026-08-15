import SwiftUI

struct SavedFolderTabRows: View {
    let configuration: SavedFolderGroupConfiguration
    let interaction: SavedFolderGroupInteractionContext

    private var keptCollapsedTab: BrowserTab? {
        configuration.keptCollapsedTab(
            for: interaction.collapsedTabVisibility.wrappedValue
        )
    }

    var body: some View {
        Group {
            if interaction.isExpanded.wrappedValue {
                ForEach(configuration.items) { item in
                    switch item {
                    case .tab(let tab):
                        SavedFolderTabRow(
                            configuration: configuration,
                            tab: tab,
                            isLoaded: configuration.pages.containsResidentPage(
                                for: tab.id
                            ),
                            unload: { tabID in
                                configuration.pages.unloadPage(
                                    for: tabID,
                                    matching: configuration.assignment
                                )
                            }
                        )
                    case .splitGroup(let groupID, let members):
                        SavedFolderSplitGroupRow(
                            configuration: configuration,
                            groupID: groupID,
                            members: members
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let keptCollapsedTab {
                SavedFolderTabRow(
                    configuration: configuration,
                    tab: keptCollapsedTab,
                    isLoaded: true,
                    unload: interaction.unloadKeptCollapsedTab
                )
                .transition(.opacity)
            }
        }
    }
}

#Preview("Saved Folder Tabs") {
    @Previewable @State var isExpanded = true
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? = nil
    @Previewable @State var visibility =
        BrowserCollapsedFolderTabVisibilityState()
    @Previewable @FocusState var isTitleFocused: Bool

    let configuration = SavedFolderGroupPreviewFixture.configuration()
    SavedFolderTabRows(
        configuration: configuration,
        interaction: SavedFolderGroupPreviewFixture.interaction(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            collapsedTabVisibility: $visibility,
            isTitleFocused: $isTitleFocused
        )
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
