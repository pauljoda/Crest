import SwiftUI

struct BrowserManualSetupSuggestionRow: View {
    @Binding var plan: BrowserManualSetupPlan
    let suggestion: BrowserSetupSiteSuggestion
    let addedTab: BrowserTab?
    let isInExistingSpace: Bool
    let spaceID: SpaceID
    let model: BrowserManualSetupModel

    var body: some View {
        HStack(spacing: BrowserManualSetupSiteEditorMetrics.controlSpacing) {
            Image(systemName: suggestion.systemImage)
                .foregroundStyle(CrestBrandTheme.accent)
                .frame(
                    width: BrowserManualSetupSiteEditorMetrics.suggestionIconSize,
                    height: BrowserManualSetupSiteEditorMetrics.suggestionIconSize
                )
                .background(
                    CrestBrandTheme.accent.opacity(
                        BrowserManualSetupSiteEditorMetrics
                            .suggestionIconFillOpacity
                    ),
                    in: .rect(
                        cornerRadius: BrowserManualSetupSiteEditorMetrics
                            .suggestionIconCornerRadius,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: BrowserManualSetupSiteEditorMetrics.suggestionTextSpacing
            ) {
                Text(suggestion.title)
                    .foregroundStyle(.primary)
                Text(
                    suggestion.url.host(percentEncoded: false)
                        ?? suggestion.url.absoluteString
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            if let addedTab {
                BrowserManualSetupPlacementMenu(
                    plan: $plan,
                    tab: addedTab,
                    spaceID: spaceID,
                    labelSymbol: "checkmark",
                    accessibilityLabel: Text(
                        "Tab placement for \(suggestion.title)"
                    ),
                    accessibilityIdentifier:
                        BrowserManualSetupAccessibilityID
                        .suggestion(suggestion),
                    model: model
                )
            } else if isInExistingSpace {
                Text("In Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(
                        .trailing,
                        BrowserManualSetupSiteEditorMetrics
                            .existingLabelTrailingPadding
                    )
            } else {
                Button(action: addSuggestion) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.crestIcon(tint: CrestBrandTheme.accent))
                .accessibilityLabel(
                    "Add \(suggestion.title) to \(BrowserManualSetupPlacementPresentation.title(for: suggestion.defaultPlacement))"
                )
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID
                        .suggestion(suggestion)
                )
            }
        }
        .frame(
            minHeight: BrowserManualSetupSiteEditorMetrics
                .suggestionRowMinimumHeight
        )
    }

    private func addSuggestion() {
        model.addSuggestion(
            suggestion,
            to: spaceID,
            plan: $plan
        )
    }
}

#Preview("Manual Setup Suggestion Row") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan

    BrowserManualSetupSuggestionRow(
        plan: $plan,
        suggestion: BrowserManualSetupPreviewFixture.suggestion,
        addedTab: nil,
        isInExistingSpace: false,
        spaceID: BrowserManualSetupPreviewFixture.spaceID,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 560)
    .padding()
}
