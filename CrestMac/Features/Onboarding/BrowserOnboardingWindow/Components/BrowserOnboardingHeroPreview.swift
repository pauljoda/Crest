import SwiftUI

struct BrowserOnboardingHeroPreview: View {
    private let previewSpace = BrowserSession.showcase.spaces[0]

    var body: some View {
        HStack(spacing: 0) {
            BrowserSpaceSidebarPreview(space: previewSpace)
                .frame(width: 300)

            VStack(spacing: 18) {
                Spacer()
                CrestStartPageMark()
                    .frame(width: 76, height: 76)
                Text("Everything in its Space")
                    .font(BrowserOnboardingTypography.display(28))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text("Preview the result before it becomes your browser.")
                    .font(BrowserOnboardingTypography.sans(13, weight: .medium))
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
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
        .accessibilityLabel("Preview of a Crest Work Space")
    }
}

#Preview("Onboarding Hero") {
    BrowserOnboardingHeroPreview()
        .frame(width: 760, height: 460)
        .padding(32)
        .background(BrowserOnboardingPalette.parchment)
}
