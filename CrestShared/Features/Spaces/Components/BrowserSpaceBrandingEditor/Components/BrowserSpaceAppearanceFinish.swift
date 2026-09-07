import SwiftUI

struct BrowserSpaceAppearanceFinish: View {
    @Binding var branding: BrowserSpaceBranding

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BrowserSpaceFineTuningFields(branding: $branding, showsTextureControl: branding.themeMode == .gradient)
        }
    }
}
