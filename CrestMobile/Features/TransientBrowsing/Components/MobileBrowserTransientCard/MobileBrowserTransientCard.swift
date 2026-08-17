import SwiftUI

struct MobileBrowserTransientCard: View {
    let model: MobileBrowserTransientOverlayModel
    let state: MobileBrowserTransientPresentationState
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let isPhone: Bool
    @Binding var dismissalOffset: CGFloat
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        if isPhone {
            MobileBrowserTransientPhoneCard(
                model: model,
                state: state,
                safeAreaInsets: safeAreaInsets,
                dismissalOffset: $dismissalOffset,
                dismiss: dismiss,
                promote: promote
            )
        } else {
            MobileBrowserTransientTabletCard(
                model: model,
                state: state,
                availableSize: availableSize,
                safeAreaInsets: safeAreaInsets,
                dismiss: dismiss,
                promote: promote
            )
        }
    }
}
