import SwiftUI

struct BrowserSourceImportSavedTabs: View {
    let title: String
    let review: BrowserImportSpaceReview
    let sections: BrowserSourceImportPreviewSections
    let overflowTabIDs: Set<TabID>
    let duplicateTabIDs: Set<TabID>
    let duplicateDestinationName: String?
    let setIncluded: (TabID, Bool) -> Void
    let setSectionIncluded: (Set<TabID>, Bool) -> Void
    let setPlacement: (TabID, TabPlacement) -> Void

    @ViewBuilder
    var body: some View {
        if !sections.savedTabs.isEmpty {
            BrowserSourceImportSectionHeader(
                title: title,
                tabs: sections.savedTabs,
                includedTabIDs: review.includedTabIDs,
                setIncluded: setSectionIncluded
            )
            .padding(.horizontal, 13)

            ForEach(review.sourceSpace.folders) { folder in
                let tabs = sections.savedTabsByFolderID[folder.id, default: []]
                if !tabs.isEmpty {
                    BrowserImportSidebarFolderRow(folder: folder)
                    ForEach(tabs) { tab in
                        tabRow(tab)
                            .padding(.leading, 14)
                    }
                }
            }

            ForEach(sections.unfiledSavedTabs) { tabRow($0) }
        }
    }

    private func tabRow(_ tab: BrowserTab) -> some View {
        BrowserSourceImportTabRow(
            review: review,
            tab: tab,
            overflowTabIDs: overflowTabIDs,
            duplicateTabIDs: duplicateTabIDs,
            duplicateDestinationName: duplicateDestinationName,
            setIncluded: setIncluded,
            setPlacement: setPlacement
        )
    }
}

#Preview("Source Import Saved Tabs") {
    BrowserSourceImportSavedTabs(
        title: "SAVED",
        review: BrowserImportPreviewFixture.review,
        sections: BrowserSourceImportPreviewSections(
            review: BrowserImportPreviewFixture.review
        ),
        overflowTabIDs: [],
        duplicateTabIDs: [],
        duplicateDestinationName: nil,
        setIncluded: { _, _ in },
        setSectionIncluded: { _, _ in },
        setPlacement: { _, _ in }
    )
    .frame(width: 340)
    .padding()
}
