import SwiftUI

extension View {
    func crestSettingsForm(
        maxWidth: CGFloat = BrowserSettingsVisualPolicy.maximumReadableContentWidth
    ) -> some View {
        modifier(CrestPlatformSettingsFormModifier(maxWidth: maxWidth))
    }
}
