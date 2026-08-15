import SwiftUI

extension View {
    func browserAddressFieldSurface(
        progress: Double,
        isLoading: Bool,
        isEditing: Bool
    ) -> some View {
        modifier(
            BrowserAddressFieldSurface(
                progress: progress,
                isLoading: isLoading,
                isEditing: isEditing
            )
        )
    }
}
