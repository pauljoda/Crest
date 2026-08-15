import SwiftUI

struct BrowserMacOnboardingTabsPreview: View {
    private let space = BrowserSession.showcase.spaces[0]

    var body: some View {
        HStack(spacing: 0) {
            BrowserSpaceSidebarPreview(space: space)
                .frame(width: 300)
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 58, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BrowserOnboardingPalette.coral)
                Text("Keep the sidebar useful")
                    .font(BrowserOnboardingTypography.display(26))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(
                    "Pin what matters, save what can wait, and close the rest."
                )
                .font(BrowserOnboardingTypography.sans(13, weight: .medium))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(BrowserOnboardingPalette.paper)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BrowserOnboardingPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Preview of pinned, saved, and open tabs in a Crest Space"
        )
    }
}

#Preview("Tabs Artwork") {
    BrowserMacOnboardingTabsPreview()
        .frame(width: 540, height: 480)
}
