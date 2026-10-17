import AppKit
import SwiftUI

/// Reviewing what one browser brings, one Space at a time: the browser's
/// sidebar on the left, Crest's on the right wearing the look setup chose,
/// and between them what the Space brings along.
struct BrowserOnboardingReviewPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let flow: BrowserOnboardingFlow
    @Binding var customizationSpaceID: UUID?
    let back: BrowserOnboardingBackAction

    var body: some View {
        if let setupReview = flow.review,
            let review = flow.selectedReview(id: setupReview.shownSpaceID)
        {
            let spaces = flow.reviewSpaces
            VStack(spacing: 0) {
                BrowserOnboardingReviewHeader(
                    icon: sourceIcon,
                    title: setupReview.title,
                    progressLabel: flow.reviewProgressLabel(for: review),
                    spaces: spaces,
                    shownSpaceID: review.id,
                    show: { show($0) }
                )
                .disabled(flow.isCommittingImport)

                BrowserOnboardingReviewSpacePage(
                    flow: flow,
                    application: setupReview.source,
                    spaces: spaces,
                    review: review,
                    leftOut: setupReview.leftOut,
                    customize: { customizationSpaceID = review.id }
                )
                .id(review.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(flow.isCommittingImport)

                BrowserOnboardingFooter(back: back, isBackDisabled: flow.isCommittingImport) {
                    HStack(spacing: 22) {
                        if let failure = flow.failure?.message {
                            Label {
                                BrowserOnboardingFailureMessage(message: failure)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(CrestTypography.sans(12, weight: .medium))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .accessibilityIdentifier("onboarding-workflow-error")
                        } else if let summary = flow.reviewSummary() {
                            Text(summary)
                                .font(CrestTypography.sans(13, weight: .medium))
                                .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.7))
                        }
                        BrowserOnboardingContinueButton(reviewActionTitle(in: setupReview)) {
                            advanceReviewOrImport(setupReview)
                        }
                        .disabled(
                            flow.isCommittingImport || (setupReview.showsLastSpace && !setupReview.hasIncludedSpaces)
                        )
                        .accessibilityIdentifier(
                            setupReview.showsLastSpace ? "onboarding-confirm-import" : "onboarding-review-next-space")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Nothing to Review",
                systemImage: "checklist.unchecked",
                description: Text("Choose a browser to build an import review.")
            )
        }
    }

    private var sourceIcon: NSImage? {
        flow.review.flatMap { flow.offeredSource($0.source) }?.icon
    }

    private func show(_ spaceID: UUID) {
        withAnimation(motion(CrestMotion.onboardingProgress)) {
            flow.shownReviewSpaceID = spaceID
        }
    }

    private func reviewActionTitle(in review: SetupImportReview) -> Text {
        if flow.isCommittingImport { return Text("Importing…") }
        return review.showsLastSpace ? Text(flow.importReviewActionTitle) : Text("Next Space")
    }

    private func advanceReviewOrImport(_ review: SetupImportReview) {
        if !review.showsLastSpace, let nextID = review.nextSpaceID {
            show(nextID)
        } else {
            flow.commitReviewedImport()
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

/// The browser under review and its Spaces as chips, the shown one lit.
private struct BrowserOnboardingReviewHeader: View {
    let icon: NSImage?
    let title: String
    let progressLabel: String
    let spaces: [BrowserImportSpaceReview]
    let shownSpaceID: UUID
    let show: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Review \(title)")
                    .font(CrestTypography.display(30))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(progressLabel)
                    .font(CrestTypography.sans(12, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
            }
            Spacer(minLength: 20)
            if spaces.count > 1 {
                HStack(spacing: 8) {
                    ForEach(spaces) { item in
                        BrowserOnboardingSpaceChip(
                            space: item.sourceSpace, isSelected: item.id == shownSpaceID, select: { show(item.id) })
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Spaces in this review")
            }
        }
        .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// One Space as a chip: its icon and name, lit when it is the one shown.
struct BrowserOnboardingSpaceChip: View {
    let space: BrowserSpaceIdentity
    let isSelected: Bool
    let select: () -> Void

    init(space: some BrowserSpaceIdentifying, isSelected: Bool, select: @escaping () -> Void) {
        self.space = space.identity
        self.isSelected = isSelected
        self.select = select
    }

    var body: some View {
        Button(action: select) {
            BrowserSpaceIdentityLabel(identity: space, iconSize: 18)
                .font(CrestTypography.sans(13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? CrestBrandPalette.ink : CrestBrandTheme.textDisplay)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: 34)
                .background(isSelected ? CrestBrandPalette.paper : CrestBrandPalette.paper.opacity(0.1), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(CrestBrandTheme.line, lineWidth: isSelected ? 0 : CrestLayout.hairline)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What an import leaves out, behind a count: each profile or Space the
/// browser held that Crest cannot bring, with why.
struct BrowserOnboardingReviewLeftOutMenu: View {
    let leftOut: [ImportLeftOut]

    var body: some View {
        Menu {
            ForEach(Array(leftOut.enumerated()), id: \.offset) { _, item in
                Section(item.name) {
                    Text(item.reason.explanation)
                }
            }
        } label: {
            Label {
                Text(BrowserOnboardingSummary.leftOutCount(leftOut.count))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(CrestTypography.sans(12, weight: .semibold))
            .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHint("Shows what the import leaves out and why")
    }
}
