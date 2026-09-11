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

            textColor
            folderColor
        }
    }

    private var textColor: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Picker("Text color", selection: $branding.textColorMode) {
                Label("Automatic", systemImage: "sparkles")
                    .tag(BrowserSpaceTextColorMode.automatic)
                Label("Light", systemImage: "sun.max.fill")
                    .tag(BrowserSpaceTextColorMode.light)
                Label("Dark", systemImage: "moon.fill")
                    .tag(BrowserSpaceTextColorMode.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("space-text-color-mode")
            Text("Automatic chooses text contrast from this Space’s colors. Light and Dark override it.")
                .font(CrestTypography.metadata)
                .foregroundStyle(CrestColor.textSecondary)
        }
    }

    private var folderColor: some View {
        CrestSettingSlider(
            "Folder color intensity",
            value: CrestSettingValue(
                $branding.folderColorIntensity,
                default: BrowserSpaceBrandingDefaults.folderColorIntensity),
            readout: .percent(zero: "Subtle", full: "Opaque"),
            identifier: "space-folder-color-intensity"
        )
    }
}
