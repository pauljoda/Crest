import SwiftUI

struct BrowserManualSetupContent: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let existingSession: BrowserSession
    let model: BrowserManualSetupModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let layout = BrowserManualSetupLayout(
                horizontalSizeClass: horizontalSizeClass,
                size: geometry.size
            )
            let previewSession = model.previewSession(
                for: plan,
                mergingInto: existingSession
            )

            Group {
                if layout.isCompact {
                    BrowserManualSetupCompactLayout(
                        plan: $plan,
                        selectedSpaceID: $selectedSpaceID,
                        existingSession: existingSession,
                        previewSession: previewSession,
                        model: model
                    )
                } else {
                    BrowserManualSetupWideLayout(
                        plan: $plan,
                        selectedSpaceID: $selectedSpaceID,
                        existingSession: existingSession,
                        previewSession: previewSession,
                        detailHeight: layout.detailHeight,
                        model: model
                    )
                }
            }
        }
    }
}

#Preview("Manual Setup Content") {
    @Previewable @State var plan = BrowserManualSetupPreviewFixture.plan
    @Previewable @State var selectedSpaceID =
        BrowserManualSetupPreviewFixture.selectedSpaceID

    BrowserManualSetupContent(
        plan: $plan,
        selectedSpaceID: $selectedSpaceID,
        existingSession: BrowserManualSetupPreviewFixture.existingSession,
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 1_080, height: 720)
}
