import SwiftUI

/// How strongly a grain lies over a Space's sidebar, from none to full,
/// whatever the sidebar's mode.
struct BrowserSpaceTextureRow: View {
    @Binding var branding: SpaceBranding

    var body: some View {
        CrestSettingSlider(
            "Texture", value: texture, readout: .percent(zero: "None", full: "Full"),
            identifier: "space-sidebar-texture")
    }

    private var texture: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { branding.textureStrength },
                set: { strength in
                    $branding.editorUpdate {
                        $0.textureStrength = strength
                        $0.hasCustomAppearance = true
                    }
                }),
            default: 0)
    }
}

#if DEBUG
    #Preview("Texture") {
        @Previewable @State var none = SpaceHouse.winter.look
        @Previewable @State var textured = {
            var look = SpaceHouse.winter.look
            look.textureStrength = 0.6
            return look
        }()
        Form {
            BrowserSpaceTextureRow(branding: $none)
            BrowserSpaceTextureRow(branding: $textured)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
    }
#endif
