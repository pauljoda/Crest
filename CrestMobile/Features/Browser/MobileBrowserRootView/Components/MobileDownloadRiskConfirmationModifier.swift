import SwiftUI

struct MobileDownloadRiskConfirmationModifier: ViewModifier {
    @Bindable var confirmation: MobileDownloadRiskConfirmationCoordinator

    func body(content: Content) -> some View {
        content.alert(
            confirmation.request?.title ?? "Download file?",
            isPresented: $confirmation.isPresented
        ) {
            Button("Cancel", role: .cancel) {
                confirmation.cancel()
            }
            Button("Download", role: .destructive) {
                confirmation.approve()
            }
        } message: {
            if let request = confirmation.request {
                Text(request.message)
            }
        }
    }
}

#Preview("Download Risk Confirmation") {
    Text("Downloads")
        .modifier(
            MobileDownloadRiskConfirmationModifier(
                confirmation: MobileDownloadRiskConfirmationCoordinator()
            )
        )
}
