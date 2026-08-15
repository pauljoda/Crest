import SwiftUI

struct BrowserManualSetupPopularSites: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    let existingSession: BrowserSession
    let model: BrowserManualSetupModel

    private let suggestions = BrowserSetupSiteSuggestion.popular

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupSiteEditorMetrics.sectionSpacing
        ) {
            HStack(
                spacing: BrowserManualSetupSiteEditorMetrics.popularHeadingSpacing
            ) {
                Capsule()
                    .fill(CrestBrandTheme.accent)
                    .frame(
                        width: BrowserManualSetupSiteEditorMetrics.popularRuleWidth,
                        height: BrowserManualSetupSiteEditorMetrics.popularRuleHeight
                    )
                Text("Popular sites")
                    .font(.subheadline.weight(.semibold))
            }

            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    BrowserManualSetupSuggestionRow(
                        plan: $plan,
                        suggestion: suggestion,
                        addedTab: model.addedSuggestionTab(
                            suggestion,
                            in: spaceID,
                            plan: plan
                        ),
                        isInExistingSpace: model.existingContainsSuggestion(
                            suggestion,
                            in: spaceID,
                            existingSession: existingSession
                        ),
                        spaceID: spaceID,
                        model: model
                    )
                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(
                                .leading,
                                BrowserManualSetupSiteEditorMetrics
                                    .dividerLeadingPadding
                            )
                    }
                }
            }
            .padding(
                .horizontal,
                BrowserManualSetupSiteEditorMetrics.listHorizontalPadding
            )
            .browserOnboardingPanel()
        }
    }
}

#Preview("Manual Setup Popular Sites") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupPopularSites(
        plan: $plan,
        spaceID: BrowserManualSetupPreviewFixture.spaceID,
        existingSession: BrowserManualSetupPreviewFixture.existingSession,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 620)
    .padding()
}
