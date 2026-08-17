import SwiftUI

struct BrowserManualSetupCompactLayout: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let existingSession: BrowserSession
    let previewSession: BrowserSession?
    let model: BrowserManualSetupModel

    var body: some View {
        let draft = model.selectedDraft(
            in: plan,
            selectedSpaceID: selectedSpaceID
        )

        ScrollView {
            VStack(spacing: CrestSpacing.medium) {
                BrowserManualSetupSidebarPreview(
                    draft: draft,
                    previewSession: previewSession,
                    model: model
                )
                .frame(height: BrowserManualSetupLayoutMetrics.compactPreviewHeight)

                BrowserManualSetupSpacePicker(
                    plan: $plan,
                    selectedSpaceID: $selectedSpaceID,
                    previewSession: previewSession,
                    model: model
                )

                BrowserManualSetupEditor(
                    plan: $plan,
                    draft: draft,
                    existingSession: existingSession,
                    compact: true,
                    model: model
                )
                .padding(.top, CrestSpacing.small)
            }
            .padding(
                .horizontal,
                BrowserManualSetupLayoutMetrics.compactHorizontalPadding
            )
            .padding(
                .vertical,
                BrowserManualSetupLayoutMetrics.verticalPadding
            )
        }
    }
}
