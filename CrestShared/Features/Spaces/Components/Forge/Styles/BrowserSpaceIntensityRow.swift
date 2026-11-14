import SwiftUI

/// How strongly a Space's sidebar wears its colors over the window, from
/// none to their full color, which is where a new look starts.
struct BrowserSpaceIntensityRow: View {
    @Binding var branding: SpaceBranding

    var body: some View {
        CrestSettingSlider(
            "Intensity", value: intensity, readout: .percent(zero: "None", full: "Full"),
            identifier: "space-sidebar-intensity")
    }

    private var intensity: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { branding.bannerStrength },
                set: { strength in
                    $branding.editorUpdate {
                        $0.bannerStrength = strength
                        $0.hasCustomAppearance = true
                    }
                }),
            default: 1)
    }
}

#if DEBUG
    #Preview("Intensity") {
        @Previewable @State var full = SpaceHouse.winter.look
        @Previewable @State var reduced = {
            var look = SpaceHouse.winter.look
            look.bannerStrength = 0.4
            return look
        }()
        Form {
            BrowserSpaceIntensityRow(branding: $full)
            BrowserSpaceIntensityRow(branding: $reduced)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
    }
#endif
