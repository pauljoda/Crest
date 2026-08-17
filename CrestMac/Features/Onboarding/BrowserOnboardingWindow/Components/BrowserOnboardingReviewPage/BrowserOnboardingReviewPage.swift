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

private struct BrowserOnboardingReviewToolbar: View {
    let icon: NSImage?
    let progressLabel: String
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
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
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
    let selectedSpaceID: SpaceID?

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
                        .accessibilityLabel(item.sourceSpace.name)
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
