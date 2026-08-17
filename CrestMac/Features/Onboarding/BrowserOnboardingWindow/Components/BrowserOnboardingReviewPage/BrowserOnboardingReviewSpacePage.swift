import SwiftUI

struct BrowserOnboardingReviewSpacePage: View {
    let flow: BrowserOnboardingFlow
    let browserSession: BrowserSession
    let application: BrowserImportApplication?
    let plan: BrowserImportReviewPlan
    let review: BrowserImportSpaceReview
    @Binding var selectedSourceSpaceID: SpaceID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                BrowserOnboardingPreviewCardLabel(
                    title: "BEFORE",
                    detail: "Click anything you don’t want"
                )
                BrowserSourceImportPreview(
                    application: application,
                    review: review,
                    overflowTabIDs: plan.overflowTabIDs(in: browserSession),
                    duplicateTabIDs: plan.duplicateTabIDs(in: browserSession),
                    duplicateDestinationName: flow.duplicateDestinationName(
                        for: review
                    ),
                    setIncluded: { tabID, isIncluded in
                        flow.setIncluded(
                            tabID,
                            isIncluded,
                            in: review.id
                        )
                    },
                    setSectionIncluded: { tabIDs, isIncluded in
                        flow.setIncluded(
                            tabIDs,
                            isIncluded,
                            in: review.id
                        )
                    },
                    setPlacement: { tabID, placement in
                        flow.setPlacement(
                            placement,
                            for: tabID,
                            in: review.id
                        )
                    }
                )
                .frame(width: 340)
                .frame(maxHeight: .infinity)
            }
            .frame(width: 340)

            Spacer(minLength: 8)

            BrowserOnboardingReviewSpaceControls(
                flow: flow,
                browserSession: browserSession,
                application: application,
                plan: plan,
                review: review,
                selectedSourceSpaceID: $selectedSourceSpaceID
            )

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                BrowserOnboardingPreviewCardLabel(
                    title: "AFTER",
                    detail: "A simplified Crest branding preview"
                )
                BrowserCrestImportPreview(
                    space: flow.previewDestinationSpace(for: review),
                    sourceName: application?.name ?? "Browser",
                    isSpaceIncluded: review.isIncluded,
                    matchedTabIDs: plan.matchedDestinationTabIDs(
                        for: review.id,
                        in: browserSession
                    )
                )
                .frame(width: 340)
                .frame(maxHeight: .infinity)
            }
            .frame(width: 340)
        }
        .frame(maxWidth: 1_040, maxHeight: .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(BrowserOnboardingPalette.parchment)
    }
}

private struct BrowserOnboardingPreviewCardLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BrowserOnboardingTypography.sans(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            Spacer()
            Text(detail)
                .font(
                    BrowserOnboardingTypography.sans(11, weight: .medium)
                )
                .foregroundStyle(
                    BrowserOnboardingPalette.inkSoft.opacity(0.72)
                )
        }
        .padding(.horizontal, 6)
    }
}
