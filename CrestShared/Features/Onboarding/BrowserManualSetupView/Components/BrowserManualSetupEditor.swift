import SwiftUI

struct BrowserManualSetupEditor: View {
    @Binding var plan: BrowserManualSetupPlan
    let draft: BrowserManualSetupSpaceDraft?
    let existingSession: BrowserSession
    let compact: Bool
    let model: BrowserManualSetupModel

    var body: some View {
        if let draft {
            VStack(
                alignment: .leading,
                spacing: BrowserManualSetupLayoutMetrics.editorSectionSpacing
            ) {
                BrowserManualSetupEditorHeader(
                    plan: $plan,
                    draft: draft,
                    model: model
                )

                BrowserManualSetupSpaceNameField(
                    plan: $plan,
                    spaceID: draft.id,
                    model: model
                )

                BrowserManualSetupSiteEditor(
                    plan: $plan,
                    spaceID: draft.id,
                    existingSession: existingSession,
                    model: model
                )

                let manualTabs = model.manuallyAddedTabs(in: draft)
                if !manualTabs.isEmpty {
                    BrowserManualSetupAddedTabList(
                        plan: $plan,
                        draft: draft,
                        tabs: manualTabs,
                        model: model
                    )
                }

                Divider()

                BrowserSpaceBrandingEditor(
                    branding: model.brandingBinding(
                        for: draft.id,
                        plan: $plan
                    ),
                    symbol: model.symbolBinding(
                        for: draft.id,
                        plan: $plan
                    ),
                    compact: compact,
                    showsPreview: false
                )
            }
        }
    }
}
