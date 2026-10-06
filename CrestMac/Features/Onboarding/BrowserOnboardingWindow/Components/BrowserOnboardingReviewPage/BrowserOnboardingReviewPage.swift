import AppKit
import SwiftUI

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
                BrowserOnboardingReviewToolbar(
                    icon: sourceIcon,
                    progressLabel: flow.reviewProgressLabel(for: review),
                    leftOut: setupReview.leftOut,
                    customize: { customizationSpaceID = review.id }
                )
                .disabled(flow.isCommittingImport)

                ZStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(spaces) { item in
                                BrowserOnboardingReviewSpacePage(
                                    flow: flow,
                                    application: setupReview.source,
                                    spaces: spaces,
                                    review: item
                                )
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(
                        id: shownSpaceID,
                        anchor: .top
                    )
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .background(BrowserOnboardingPalette.parchment)

                    BrowserOnboardingReviewSpaceStepper(
                        spaces: spaces,
                        selectedSpaceID: setupReview.shownSpaceID
                    )
                }
                .disabled(flow.isCommittingImport)

                BrowserOnboardingReviewFooter(
                    failure: flow.failure?.message,
                    summary: flow.reviewSummary(),
                    isCommitting: flow.isCommittingImport,
                    isFinalSpace: setupReview.showsLastSpace,
                    isImportDisabled: !setupReview.hasIncludedSpaces,
                    actionTitle: reviewActionTitle(in: setupReview),
                    back: back.action,
                    advance: { advanceReviewOrImport(setupReview) }
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
        flow.review.flatMap { flow.offeredSource($0.source) }?.icon
    }

    /// The Space the person is looking at, which setup holds.
    private var shownSpaceID: Binding<UUID?> {
        Binding(
            get: { flow.shownReviewSpaceID },
            set: { flow.shownReviewSpaceID = $0 }
        )
    }

    private func reviewActionTitle(
        in review: SetupImportReview
    ) -> LocalizedStringResource {
        if flow.isCommittingImport { return "Importing…" }
        return review.showsLastSpace
            ? flow.importReviewActionTitle
            : "Next Space"
    }

    private func advanceReviewOrImport(_ review: SetupImportReview) {
        if !review.showsLastSpace, let nextID = review.nextSpaceID {
            withAnimation(motion(CrestMotion.onboardingProgress)) {
                flow.shownReviewSpaceID = nextID
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

private struct BrowserOnboardingReviewToolbar: View {
    let icon: NSImage?
    let progressLabel: String
    /// What the browser held that the import cannot bring, and why.
    let leftOut: [ImportLeftOut]
    let customize: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Review before importing")
                    .font(
                        BrowserOnboardingTypography.sans(14, weight: .bold)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                HStack(spacing: 6) {
                    Text(progressLabel)
                        .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    if !leftOut.isEmpty {
                        Text(verbatim: "·")
                            .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                        BrowserOnboardingReviewLeftOutMenu(leftOut: leftOut)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            Button(
                "Customize Space",
                systemImage: "paintpalette",
                action: customize
            )
            .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 78)
        .background(BrowserOnboardingPalette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(height: 1)
        }
    }
}

private struct BrowserOnboardingReviewSpaceStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spaces: [BrowserImportSpaceReview]
    let selectedSpaceID: UUID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(width: 1)
            VStack(spacing: 12) {
                ForEach(spaces) { item in
                    let isCurrent = item.id == selectedSpaceID
                    Capsule(style: .continuous)
                        .fill(
                            isCurrent
                                ? BrowserOnboardingPalette.coral
                                : BrowserOnboardingPalette.inkSoft.opacity(0.34)
                        )
                        .frame(
                            width: isCurrent ? 10 : 7,
                            height: isCurrent ? 34 : 7
                        )
                        .animation(
                            motion(CrestMotion.onboardingProgress),
                            value: selectedSpaceID
                        )
                        .accessibilityLabel(item.sourceSpace.settings.name)
                        .accessibilityValue(
                            isCurrent ? "Current Space" : "Space in review"
                        )
                }
            }
            .padding(.vertical, 10)
            .background(BrowserOnboardingPalette.parchment)
        }
        .fixedSize()
        .padding(.trailing, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space review progress")
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

private struct BrowserOnboardingReviewFooter: View {
    let failure: BrowserOnboardingFailureText?
    let summary: LocalizedStringResource?
    let isCommitting: Bool
    let isFinalSpace: Bool
    let isImportDisabled: Bool
    let actionTitle: LocalizedStringResource
    let back: () -> Void
    let advance: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: back)
                .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                .disabled(isCommitting)
                .accessibilityIdentifier("onboarding-back")
            Spacer()
            if let failure {
                Label {
                    BrowserOnboardingFailureMessage(message: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(BrowserOnboardingTypography.sans(11, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(2)
                .accessibilityIdentifier("onboarding-workflow-error")
            } else if let summary {
                Text(summary)
                    .font(
                        BrowserOnboardingTypography.sans(
                            12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            }
            Button(action: advance) {
                Text(actionTitle)
            }
            .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(isCommitting || (isFinalSpace && isImportDisabled))
            .accessibilityIdentifier(
                isFinalSpace
                    ? "onboarding-confirm-import"
                    : "onboarding-review-next-space"
            )
        }
        .padding(18)
        .background(BrowserOnboardingPalette.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(height: 1)
        }
    }
}

/// What an import leaves out, behind a count: each profile or Space the
/// browser held that Crest cannot bring, with why.
private struct BrowserOnboardingReviewLeftOutMenu: View {
    let leftOut: [ImportLeftOut]

    var body: some View {
        Menu {
            ForEach(Array(leftOut.enumerated()), id: \.offset) { _, item in
                Section(item.name) {
                    Text(item.reason.explanation)
                }
            }
        } label: {
            Text(BrowserOnboardingSummary.leftOutCount(leftOut.count))
                .foregroundStyle(BrowserOnboardingPalette.coral)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHint("Shows what the import leaves out and why")
    }
}
