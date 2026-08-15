import AppKit
import SwiftUI

struct BrowserOnboardingReviewPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let flow: BrowserOnboardingFlow
    let browserSession: BrowserSession
    let application: BrowserImportApplication?
    let sources: [BrowserInstalledImportSource]
    @Binding var selectedSourceSpaceID: SpaceID?
    @Binding var customizationSpaceID: SpaceID?
    let back: () -> Void

    var body: some View {
        if let plan = flow.plan,
            let review = flow.selectedReview(id: selectedSourceSpaceID)
        {
            VStack(spacing: 0) {
                BrowserOnboardingReviewToolbar(
                    icon: sourceIcon,
                    progressLabel: flow.reviewProgressLabel(for: review),
                    customize: { customizationSpaceID = review.id }
                )
                .disabled(flow.isCommittingImport)

                ZStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(plan.spaces) { item in
                                BrowserOnboardingReviewSpacePage(
                                    flow: flow,
                                    browserSession: browserSession,
                                    application: application,
                                    plan: plan,
                                    review: item,
                                    selectedSourceSpaceID:
                                        $selectedSourceSpaceID
                                )
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(
                        id: $selectedSourceSpaceID,
                        anchor: .top
                    )
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .background(BrowserOnboardingPalette.parchment)

                    BrowserOnboardingReviewSpaceStepper(
                        spaces: plan.spaces,
                        selectedSpaceID: selectedSourceSpaceID
                    )
                }
                .disabled(flow.isCommittingImport)

                BrowserOnboardingReviewFooter(
                    failure: flow.failure?.message,
                    summary: flow.reviewSummary(),
                    isCommitting: flow.isCommittingImport,
                    isFinalSpace: isFinalSpace(in: plan),
                    isImportDisabled: plan.spaces.allSatisfy {
                        !$0.isIncluded
                    },
                    actionTitle: reviewActionTitle(in: plan),
                    back: back,
                    advance: { advanceReviewOrImport(plan) }
                )
            }
        } else {
            ContentUnavailableView(
                "Nothing to Review",
                systemImage: "checklist.unchecked",
                description: Text(
                    "Choose a browser session to build an import review."
                )
            )
        }
    }

    private var sourceIcon: NSImage? {
        sources.first { $0.application == application }?.icon
    }

    private func isFinalSpace(in plan: BrowserImportReviewPlan) -> Bool {
        BrowserImportReviewNavigation.isFinalSpace(
            selectedSourceSpaceID,
            in: plan.spaces.map(\.id)
        )
    }

    private func reviewActionTitle(
        in plan: BrowserImportReviewPlan
    ) -> LocalizedStringResource {
        if flow.isCommittingImport { return "Importing…" }
        return isFinalSpace(in: plan)
            ? flow.importReviewActionTitle
            : "Next Space"
    }

    private func advanceReviewOrImport(_ plan: BrowserImportReviewPlan) {
        if let nextID = BrowserImportReviewNavigation.nextSpaceID(
            after: selectedSourceSpaceID,
            in: plan.spaces.map(\.id)
        ) {
            withAnimation(motion(CrestMotion.onboardingProgress)) {
                selectedSourceSpaceID = nextID
            }
        } else {
            flow.commitReviewedImport()
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

#Preview("Import Review Page") {
    @Previewable @State var selectedSourceSpaceID: SpaceID? =
        BrowserOnboardingWindowPreviewFixture.reviewPlan.spaces.first?.id
    @Previewable @State var customizationSpaceID: SpaceID? = nil
    let fixture = BrowserOnboardingWindowPreviewFixture(
        plan: BrowserOnboardingWindowPreviewFixture.reviewPlan
    )

    BrowserOnboardingReviewPage(
        flow: fixture.flow,
        browserSession: fixture.browser.session,
        application: .arc,
        sources: [BrowserOnboardingWindowPreviewFixture.importSource],
        selectedSourceSpaceID: $selectedSourceSpaceID,
        customizationSpaceID: $customizationSpaceID,
        back: {}
    )
    .frame(width: 1_080, height: 604)
}
