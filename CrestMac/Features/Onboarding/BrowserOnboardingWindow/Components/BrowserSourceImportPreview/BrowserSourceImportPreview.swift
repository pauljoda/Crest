import SwiftUI

struct BrowserSourceImportPreview: View {
    let application: BrowserImportApplication?
    let review: BrowserImportSpaceReview
    let overflowTabIDs: Set<TabID>
    let duplicateTabIDs: Set<TabID>
    let duplicateDestinationName: String?
    let setIncluded: (TabID, Bool) -> Void
    let setSectionIncluded: (Set<TabID>, Bool) -> Void
    let setPlacement: (TabID, TabPlacement) -> Void

    var body: some View {
        BrowserImportSidebarFrame(branding: review.sourceSpace.branding) {
            BrowserSourceImportContent(
                application: application,
                review: review,
                sections: BrowserSourceImportPreviewSections(review: review),
                overflowTabIDs: overflowTabIDs,
                duplicateTabIDs: duplicateTabIDs,
                duplicateDestinationName: duplicateDestinationName,
                setIncluded: setIncluded,
                setSectionIncluded: setSectionIncluded,
                setPlacement: setPlacement
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(application?.name ?? "Source browser") \(review.sourceSpace.name) sidebar before import"
        )
    }
}

#Preview("Source Browser Import") {
    BrowserSourceImportPreview(
        application: .arc,
        review: BrowserImportPreviewFixture.review,
        overflowTabIDs: [],
        duplicateTabIDs: [],
        duplicateDestinationName: nil,
        setIncluded: { _, _ in },
        setSectionIncluded: { _, _ in },
        setPlacement: { _, _ in }
    )
    .frame(width: 340, height: 620)
    .padding()
    .background(BrowserOnboardingPalette.parchment)
}
