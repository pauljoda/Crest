import SwiftUI

struct BrowserManualSetupSidebarPreview: View {
    let draft: BrowserManualSetupSpaceDraft?
    let previewSession: BrowserSession?
    let model: BrowserManualSetupModel

    var body: some View {
        Group {
            if let draft {
                BrowserSpaceSidebarPreview(
                    space: model.previewSpace(
                        for: draft,
                        in: previewSession
                    )
                )
                .transition(
                    .opacity.combined(
                        with: .scale(
                            scale: BrowserManualSetupLayoutMetrics
                                .previewTransitionScale
                        )
                    )
                )
                .id(draft.id)
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.sidebarPreview
                )
            } else {
                ContentUnavailableView(
                    "Add a Space",
                    systemImage: "square.grid.2x2",
                    description: Text(
                        "Create a Space to start shaping your browser."
                    )
                )
            }
        }
    }
}
