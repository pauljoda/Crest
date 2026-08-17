import SwiftUI

struct BrowserManualSetupWideLayout: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let existingSession: BrowserSession
    let previewSession: BrowserSession?
    let detailHeight: CGFloat
    let model: BrowserManualSetupModel

    var body: some View {
        let draft = model.selectedDraft(
            in: plan,
            selectedSpaceID: selectedSpaceID
        )

        HStack(
            alignment: .top,
            spacing: BrowserManualSetupLayoutMetrics.wideColumnSpacing
        ) {
            VStack(spacing: CrestSpacing.medium) {
                BrowserManualSetupSidebarPreview(
                    draft: draft,
                    previewSession: previewSession,
                    model: model
                )
                .frame(width: BrowserManualSetupLayoutMetrics.previewColumnWidth)
                .frame(maxHeight: .infinity)

                BrowserManualSetupSpacePicker(
                    plan: $plan,
                    selectedSpaceID: $selectedSpaceID,
                    previewSession: previewSession,
                    model: model
                )
            }
            .frame(
                width: BrowserManualSetupLayoutMetrics.previewColumnWidth,
                height: detailHeight
            )

            ScrollView {
                BrowserManualSetupEditor(
                    plan: $plan,
                    draft: draft,
                    existingSession: existingSession,
                    compact: false,
                    model: model
                )
                .padding(
                    .bottom,
                    BrowserManualSetupLayoutMetrics.editorBottomPadding
                )
            }
            .frame(
                maxWidth: BrowserManualSetupLayoutMetrics.editorMaximumWidth,
                maxHeight: detailHeight
            )
        }
        .frame(
            maxWidth: BrowserManualSetupLayoutMetrics.contentMaximumWidth,
            maxHeight: detailHeight,
            alignment: .top
        )
        .padding(
            .horizontal,
            BrowserManualSetupLayoutMetrics.wideHorizontalPadding
        )
        .padding(
            .vertical,
            BrowserManualSetupLayoutMetrics.verticalPadding
        )
    }
}
