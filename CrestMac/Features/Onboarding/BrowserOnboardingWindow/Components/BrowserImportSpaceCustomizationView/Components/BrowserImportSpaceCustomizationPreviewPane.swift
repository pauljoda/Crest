import SwiftUI

struct BrowserImportSpaceCustomizationPreviewPane: View {
    let space: BrowserSpace?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BRANDING PREVIEW")
                .font(BrowserOnboardingTypography.sans(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                .padding(.leading, 6)
            BrowserCrestImportPreview(
                space: space,
                sourceName: "this Space"
            )
            .frame(width: 340)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}
