import SwiftUI

struct MobileSpaceCustomizationPreview: View {
    let space: BrowserSpace
    let wide: Bool

    var body: some View {
        BrowserSpaceSidebarPreview(space: space)
            .frame(width: wide ? 210 : nil)
            .frame(maxWidth: wide ? nil : .infinity)
            .frame(height: wide ? 430 : 390)
            .accessibilityIdentifier("mobile-space-customization-preview")
    }
}
