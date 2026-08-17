import SwiftUI

struct BrowserSpaceForgeCrestSteps: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        Group {
            BrowserSpaceShieldStep(branding: $branding, compact: compact)
            BrowserSpaceFieldDivisionStep(branding: $branding, compact: compact)
            BrowserSpaceOrdinaryStep(branding: $branding, compact: compact)
            BrowserSpaceChargeStep(branding: $branding, compact: compact)
            BrowserSpaceTrimStep(branding: $branding, compact: compact)
        }
    }
}
