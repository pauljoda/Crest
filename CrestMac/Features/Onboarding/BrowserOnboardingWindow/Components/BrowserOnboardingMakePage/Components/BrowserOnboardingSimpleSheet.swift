import SwiftUI

/// What a first run changes on a simple Space: the one color its sidebar and
/// icon wear, and its icon.
struct BrowserOnboardingSimpleSheet: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            BrowserOnboardingMakeSection("Color") {
                BrowserOnboardingMakeStrip {
                    ForEach(BrowserSimpleSpaceColor.all, id: \.self) { color in
                        BrowserSimpleSpaceColorSwatch(
                            color: color, isSelected: BrowserSimpleSpaceColor.worn(by: branding) == color,
                            diameter: 44, tint: CrestBrandPalette.butter
                        ) {
                            $branding.editorUpdate { $0 = color.applied(to: $0) }
                        }
                    }
                    BrowserSimpleSpaceCustomColor(branding: $branding, diameter: 44, tint: CrestBrandPalette.butter)
                }
            }
            BrowserOnboardingIconSection(branding: $branding, symbol: $symbol)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
