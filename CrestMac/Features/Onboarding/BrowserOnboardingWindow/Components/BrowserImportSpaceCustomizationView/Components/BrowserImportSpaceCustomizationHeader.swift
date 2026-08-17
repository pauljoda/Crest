import SwiftUI

struct BrowserImportSpaceCustomizationHeader: View {
    let done: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button("Back to review", systemImage: "chevron.left", action: done)
                .buttonStyle(.borderless)

            Divider()
                .frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Make this Space yours")
                    .font(BrowserOnboardingTypography.sans(14, weight: .bold))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text("Every change appears in the Crest branding preview.")
                    .font(BrowserOnboardingTypography.sans(11, weight: .medium))
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            }

            Spacer()

            Button("Done Customizing", systemImage: "checkmark", action: done)
                .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(BrowserOnboardingPalette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(height: 1)
        }
    }
}
