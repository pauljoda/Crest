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

    /// The Space the scroll shows. Setup learns it once the scroll settles,
    /// so moving through the review changes nothing setup holds mid-scroll.
    @State private var scrolledSpaceID: UUID?

    var body: some View {
        if let setupReview = flow.review,
            let review = flow.selectedReview(id: scrolledSpaceID ?? setupReview.shownSpaceID)
        {
            let spaces = flow.reviewSpaces
            VStack(spacing: 0) {
                BrowserOnboardingReviewHeader(
                    icon: sourceIcon,
                    title: setupReview.title,
                    progressLabel: flow.reviewProgressLabel(for: review)
                )
                .disabled(flow.isCommittingImport)

                // The browser's Spaces stack under one another, one page each,
                // so moving between them reads as moving through that browser.
                ZStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(spaces) { item in
                                BrowserOnboardingReviewSpacePage(
                                    flow: flow,
                                    application: setupReview.source,
                                    spaces: spaces,
                                    review: item,
                                    leftOut: setupReview.leftOut,
                                    customize: { customizationSpaceID = item.id }
                                )
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrolledSpaceID, anchor: .top)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle, let scrolledSpaceID { flow.shownReviewSpaceID = scrolledSpaceID }
                    }

                    BrowserOnboardingReviewSpaceStepper(spaces: spaces, selectedSpaceID: review.id)
                }
                .disabled(flow.isCommittingImport)
                .onAppear { scrolledSpaceID = setupReview.shownSpaceID }
                .onChange(of: setupReview.shownSpaceID) { _, shown in
                    if let shown, shown != scrolledSpaceID { scrolledSpaceID = shown }
                }

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
                        let isLast = review.id == spaces.last?.id
                        BrowserOnboardingContinueButton(reviewActionTitle(isLast: isLast)) {
                            advanceReviewOrImport(from: review, in: spaces)
                        }
                        .disabled(flow.isCommittingImport || (isLast && !setupReview.hasIncludedSpaces))
                        .accessibilityIdentifier(isLast ? "onboarding-confirm-import" : "onboarding-review-next-space")
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

    /// Scrolls to `spaceID`, and tells setup once the scroll arrives, unless
    /// a later press or a scroll has moved on from it by then.
    private func show(_ spaceID: UUID) {
        withAnimation(motion(CrestMotion.onboardingProgress)) {
            scrolledSpaceID = spaceID
        } completion: {
            if scrolledSpaceID == spaceID { flow.shownReviewSpaceID = spaceID }
        }
    }

    private func reviewActionTitle(isLast: Bool) -> Text {
        if flow.isCommittingImport { return Text("Importing…") }
        return isLast ? Text(flow.importReviewActionTitle) : Text("Next Space")
    }

    /// Shows the Space after `review` among `spaces`, or imports from the last.
    private func advanceReviewOrImport(from review: BrowserImportSpaceReview, in spaces: [BrowserImportSpaceReview]) {
        if let index = spaces.firstIndex(where: { $0.id == review.id }), index + 1 < spaces.count {
            show(spaces[index + 1].id)
        } else {
            flow.commitReviewedImport()
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

/// The browser under review, and which of its Spaces this is.
private struct BrowserOnboardingReviewHeader: View {
    let icon: NSImage?
    let title: String
    let progressLabel: String

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
        }
        .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// Where the shown Space stands among the browser's, down the right edge.
private struct BrowserOnboardingReviewSpaceStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spaces: [BrowserImportSpaceReview]
    let selectedSpaceID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(groups, id: \.[0].id) { group in
                // The Spaces that come in as one group share an outline.
                VStack(spacing: 12) {
                    ForEach(group) { item in step(item) }
                }
                .padding(group.count > 1 ? 5 : 0)
                .overlay {
                    if group.count > 1 {
                        Capsule(style: .continuous)
                            .strokeBorder(CrestBrandPalette.paper.opacity(0.35), lineWidth: CrestLayout.hairline)
                    }
                }
            }
        }
        .padding(.trailing, BrowserOnboardingStageMetrics.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space review progress")
    }

    /// The reviewed Spaces in order, split where one group ends and the next
    /// begins. Spaces the review leaves out stand on their own.
    private var groups: [[BrowserImportSpaceReview]] {
        var groups: [[BrowserImportSpaceReview]] = []
        for item in spaces {
            if let last = groups.last?.last, last.isIncluded, item.isIncluded, last.groupID == item.groupID {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups
    }

    private func step(_ item: BrowserImportSpaceReview) -> some View {
        let isCurrent = item.id == selectedSpaceID
        return Capsule(style: .continuous)
            .fill(isCurrent ? CrestBrandPalette.butter : CrestBrandPalette.paper.opacity(0.3))
            .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 32 : 6)
            .animation(CrestMotion.onboardingProgress.unlessReducingMotion(reduceMotion), value: selectedSpaceID)
            .accessibilityLabel(item.sourceSpace.settings.name)
            .accessibilityValue(isCurrent ? "Current Space" : "Space in review")
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
