import SwiftUI

struct BrowserSourceImportContent: View {
    let application: BrowserImportApplication?
    let review: BrowserImportSpaceReview
    let sections: BrowserSourceImportPreviewSections
    let overflowTabIDs: Set<TabID>
    let duplicateTabIDs: Set<TabID>
    let duplicateDestinationName: String?
    let setIncluded: (TabID, Bool) -> Void
    let setSectionIncluded: (Set<TabID>, Bool) -> Void
    let setPlacement: (TabID, TabPlacement) -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrowserSourceImportChrome(application: application)

            if !sections.pinnedTabs.isEmpty {
                BrowserSourceImportSectionHeader(
                    title: pinnedTitle,
                    tabs: sections.pinnedTabs,
                    includedTabIDs: review.includedTabIDs,
                    setIncluded: setSectionIncluded
                )
                .padding(.horizontal, 13)
                .padding(.top, 8)
                BrowserSourceImportPinnedGrid(
                    review: review,
                    tabs: sections.pinnedTabs,
                    overflowTabIDs: overflowTabIDs,
                    duplicateTabIDs: duplicateTabIDs,
                    duplicateDestinationName: duplicateDestinationName,
                    setIncluded: setIncluded
                )
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 7)
            }

            BrowserSourceImportSpaceHeader(
                application: application,
                space: review.sourceSpace
            )

            if application == .arc, sections.currentTabs.isEmpty {
                Label("New Tab", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    BrowserSourceImportSavedTabs(
                        title: savedTitle,
                        review: review,
                        sections: sections,
                        overflowTabIDs: overflowTabIDs,
                        duplicateTabIDs: duplicateTabIDs,
                        duplicateDestinationName: duplicateDestinationName,
                        setIncluded: setIncluded,
                        setSectionIncluded: setSectionIncluded,
                        setPlacement: setPlacement
                    )

                    if !sections.savedTabs.isEmpty,
                        !sections.currentTabs.isEmpty
                    {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                    }

                    if !sections.currentTabs.isEmpty {
                        BrowserSourceImportSectionHeader(
                            title: "OPEN TABS",
                            tabs: sections.currentTabs,
                            includedTabIDs: review.includedTabIDs,
                            setIncluded: setSectionIncluded
                        )
                        .padding(.horizontal, 13)
                        ForEach(sections.currentTabs) { tab in
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
                }
            }

            BrowserSourceImportFooter()
        }
    }

    private var pinnedTitle: String {
        switch application {
        case .arc: "FAVORITES"
        case .zen: "ESSENTIALS"
        default: "PINNED"
        }
    }

    private var savedTitle: String {
        switch application {
        case .chrome, .safari: "BOOKMARKS"
        default: "SAVED"
        }
    }
}

#Preview("Source Import Content") {
    BrowserSourceImportContent(
        application: .arc,
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
    .frame(width: 340, height: 620)
}
