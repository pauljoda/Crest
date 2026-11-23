import SwiftUI

/// Mobile Settings draws its grouped form on Crest's settings canvas.
struct CrestPlatformSettingsFormModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(CrestBrandTheme.canvas)
            .frame(maxWidth: maxWidth)
    }
}
