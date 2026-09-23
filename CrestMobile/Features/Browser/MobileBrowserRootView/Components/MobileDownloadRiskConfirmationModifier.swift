import SwiftUI

/// Presents the shared risky-download confirmation for the profiles this
/// window browses.
struct MobileDownloadRiskConfirmationModifier: ViewModifier {
    @Bindable var confirmation: MobileDownloadRiskConfirmationCoordinator
    let profileIDs: Set<UUID>

    func body(content: Content) -> some View {
        content.alert(
            confirmation.request?.title ?? "Download file?",
            isPresented: Binding(
                get: { confirmation.request.map { profileIDs.contains($0.profileID) } ?? false },
                set: { confirmation.isPresented = $0 }
            )
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
