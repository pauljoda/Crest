import SwiftUI

struct MobileOnboardingSpaceCarousel: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?

    let existingSession: BrowserSession
    let horizontalSizeClass: UserInterfaceSizeClass?
    let addSpace: () -> Void
    let customize: (SpaceID) -> Void
    let remove: (SpaceID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(
                geometry.size.width * cardWidthRatio,
                MobileOnboardingLayout.setupCardMaximumWidth
            )
            let sideMargin = max(0, (geometry.size.width - cardWidth) / 2)

            ScrollView(.horizontal) {
                LazyHStack(spacing: MobileOnboardingLayout.setupCardSpacing) {
                    ForEach(plan.spaces) { draft in
                        MobileOnboardingSpaceCard(
                            previewSpace: previewSpace(for: draft),
                            name: nameBinding(for: draft.id),
                            canRemove: draft.isNew && plan.spaces.count > 1,
                            customize: { customize(draft.id) },
                            remove: { remove(draft.id) }
                        )
                        .frame(width: cardWidth, height: geometry.size.height)
                        .id(draft.id)
                    }

                    MobileOnboardingAddSpaceCard(action: addSpace)
                        .frame(width: cardWidth, height: geometry.size.height)
                        .disabled(
                            plan.spaces.count
                                >= BrowserPortableArchive.maximumSpaceCount
                        )
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedSpaceID, anchor: .center)
            .accessibilityIdentifier(
                BrowserMobileAccessibilityID.spaceCarousel
            )
        }
    }

    private var cardWidthRatio: CGFloat {
        horizontalSizeClass == .regular
            ? MobileOnboardingLayout.regularSetupCardWidthRatio
            : MobileOnboardingLayout.compactSetupCardWidthRatio
    }

    private func previewSpace(
        for draft: BrowserManualSetupSpaceDraft
    ) -> BrowserSpace {
        MobileOnboardingSpacePreviewFactory.preview(
            draft: draft,
            plan: plan,
            existingSession: existingSession,
            includesSamples: true
        )
    }

    private func nameBinding(for spaceID: SpaceID) -> Binding<String> {
        Binding(
            get: {
                plan.spaces.first { $0.id == spaceID }?
                    .customization.name ?? ""
            },
            set: { value in
                let symbol =
                    plan.spaces.first { $0.id == spaceID }?
                    .customization.symbol ?? "square.grid.2x2"
                plan.setSpaceIdentity(
                    name: value,
                    symbol: symbol,
                    for: spaceID
                )
            }
        )
    }
}

#Preview("Onboarding Space Carousel") {
    @Previewable @State var plan = MobileOnboardingPreviewFixtures.manualPlan
    @Previewable @State var selectedSpaceID =
        MobileOnboardingPreviewFixtures.manualPlan.spaces.first?.id
    let fixture = MobileBrowserPreviewFixture()
    MobileOnboardingSpaceCarousel(
        plan: $plan,
        selectedSpaceID: $selectedSpaceID,
        existingSession: fixture.browser.session,
        horizontalSizeClass: .compact,
        addSpace: {},
        customize: { _ in },
        remove: { _ in }
    )
    .frame(height: 360)
}
