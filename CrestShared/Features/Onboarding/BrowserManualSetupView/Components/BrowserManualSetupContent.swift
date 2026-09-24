import SwiftUI

struct BrowserManualSetupContent: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    let browser: BrowserStore
    let model: BrowserManualSetupModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let layout = BrowserManualSetupLayout(
                horizontalSizeClass: horizontalSizeClass,
                size: geometry.size
            )
            let existingSession = browser.session
            let previewSession = model.previewSession(for: plan, in: browser)

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
