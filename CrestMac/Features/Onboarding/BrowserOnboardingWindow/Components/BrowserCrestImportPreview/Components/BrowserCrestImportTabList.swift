import SwiftUI

struct BrowserCrestImportTabList: View {
    let space: BrowserSpace
    let matchedTabIDs: Set<TabID>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(space.folders) { folder in
                    let tabs = space.savedTabs(in: folder.id)
                    if !tabs.isEmpty {
                        BrowserImportSidebarFolderRow(folder: folder)
                        ForEach(tabs) { tab in
                            row(tab)
                                .padding(.leading, 14)
                        }
                    }
                }

                ForEach(space.unfiledSavedTabs) { row($0) }

                if !space.savedTabs.isEmpty, !space.currentTabs.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }

                if !space.currentTabs.isEmpty {
                    Label("New Tab", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 17)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 40,
                            alignment: .leading
                        )

                    ForEach(space.currentTabs) { row($0) }
                }
            }
        }
    }

    private func row(_ tab: BrowserTab) -> some View {
        BrowserImportSidebarResultTabRow(
            tab: tab,
            profileID: space.profile.id,
            isSelected: tab.id == space.selectedTabID,
            isMatched: matchedTabIDs.contains(tab.id)
        )
    }
}

#Preview("Crest Import Tab List") {
    BrowserCrestImportTabList(
        space: BrowserImportPreviewFixture.sourceSpace,
        matchedTabIDs: [BrowserImportPreviewFixture.savedTab.id]
    )
    .frame(width: 340, height: 360)
    .padding()
}
