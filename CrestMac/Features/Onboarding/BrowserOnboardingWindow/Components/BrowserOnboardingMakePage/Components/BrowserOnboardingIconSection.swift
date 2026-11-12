import SwiftUI

/// The sheet's row that gives a Space a plain icon, as the shared icon
/// controls side by side under the sheet's heading.
struct BrowserOnboardingIconSection: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    var body: some View {
        BrowserOnboardingMakeSection("Icon") {
            HStack(spacing: 12) {
                BrowserSpaceIconChoice(branding: $branding, symbol: $symbol)
            }
            .frame(maxWidth: 520)
        }
    }
}
