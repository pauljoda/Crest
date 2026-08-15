import SwiftUI

struct BrowserSpaceFineTuningFields: View {
    @Binding var branding: BrowserSpaceBranding
    let showsTextureControl: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            if showsTextureControl {
                Toggle(
                    "Texture",
                    isOn: $branding.editorShowsTexture
                )
                Text("Adds a restrained grain without changing the palette.")
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
            }

            BrowserSpaceBannerSlider(
                title: "Color intensity",
                value: $branding.editorBannerStrength,
                identifier: "space-branding-color-intensity",
                help: "Controls how strongly the chosen colors enter the sidebar."
            )
            BrowserSpaceBannerSlider(
                title: "Readability fade",
                value: $branding.editorReadabilityFade,
                identifier: "space-branding-readability-fade",
                help: "Adds contrast behind tabs and controls."
            )
        }
    }
}

#Preview("Fine Tuning Fields") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.gradientBranding

    BrowserSpaceFineTuningFields(
        branding: $branding,
        showsTextureControl: true
    )
    .frame(width: 420)
    .padding(CrestSpacing.large)
}
