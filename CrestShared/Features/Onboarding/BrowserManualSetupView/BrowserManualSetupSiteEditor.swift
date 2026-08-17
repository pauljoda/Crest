import SwiftUI

struct BrowserManualSetupSiteEditor: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    let existingSession: BrowserSession
    let model: BrowserManualSetupModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserManualSetupSiteEditorMetrics.sectionSpacing
        ) {
            Text("Add a site")
                .font(.headline)
            Text(
                "Type any website, or choose from a few popular starting points."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            BrowserManualSetupAddressRow(
                plan: $plan,
                spaceID: spaceID,
                model: model
            )

            BrowserManualSetupPlacementPicker(model: model)

            BrowserManualSetupPopularSites(
                plan: $plan,
                spaceID: spaceID,
                existingSession: existingSession,
                model: model
            )

            BrowserManualSetupErrorMessage(message: model.errorMessage)
        }
    }
}

private struct BrowserManualSetupAddressRow: View {
    @Binding var plan: BrowserManualSetupPlan
    let spaceID: SpaceID
    @Bindable var model: BrowserManualSetupModel

    var body: some View {
        HStack(spacing: BrowserManualSetupSiteEditorMetrics.controlSpacing) {
            TextField("example.com", text: $model.address)
                .crestTextField()
                .submitLabel(.done)
                .onSubmit(addTab)
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.address
                )

            Button(action: addTab) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(
                .crestIcon(
                    tint: CrestBrandTheme.accent,
                    isProminent: true
                )
            )
            .disabled(!model.canAddAddress)
            .accessibilityLabel("Add site")
            .accessibilityIdentifier(
                BrowserManualSetupAccessibilityID.addTab
            )
        }
    }

    private func addTab() {
        model.addTab(to: spaceID, plan: $plan)
    }
}

private struct BrowserManualSetupPlacementPicker: View {
    @Bindable var model: BrowserManualSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("Put new sites in")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("Put new sites in", selection: $model.placement) {
                ForEach(
                    BrowserManualSetupPlacementPresentation.choices,
                    id: \.self
                ) { choice in
                    Label(
                        BrowserManualSetupPlacementPresentation.label(for: choice),
                        systemImage:
                            BrowserManualSetupPlacementPresentation
                            .symbol(for: choice)
                    )
                    .tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .tint(CrestBrandTheme.accent)
            .accessibilityLabel("Put new sites in")
        }
    }
}

private struct BrowserManualSetupPopularSites: View {
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

private struct BrowserManualSetupSuggestionRow: View {
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

private struct BrowserManualSetupErrorMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.error
                )
        }
    }
}
