import SwiftUI

struct BrowserSpaceForgeFoundationSteps: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    let compact: Bool
    let showsPreview: Bool

    var body: some View {
        Group {
            if showsPreview {
                BrowserSpaceEditorPreview(
                    branding: branding,
                    symbol: symbol,
                    compact: compact
                )
            }

            BrowserSpaceFieldStep(branding: $branding, compact: compact)
            BrowserSpacePatternStep(branding: $branding, compact: compact)
            BrowserSpaceMarkStep(
                branding: $branding,
                symbol: $symbol,
                compact: compact
            )
        }
    }
}
