import SwiftUI

struct MobileBrowserUnavailableTransientSpaceView: View {
    let requestID: UUID
    let dismiss: () -> Void

    var body: some View {
        Color.clear
            .task(id: requestID) {
                dismiss()
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    MobileBrowserUnavailableTransientSpaceView(
        requestID: MobileBrowserTransientPreviewFixture.requestID,
        dismiss: {}
    )
}
