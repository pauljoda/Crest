import SwiftUI

struct BrowserSpaceAppearanceBackgroundChoices: View {
    @Binding var branding: BrowserSpaceBranding

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if branding.themeMode == .gradient {
                HStack(spacing: 24) {
                    BrowserSpaceGradientAngleDial(
                        angle: $branding.editorGradientAngle, color: branding.secondaryColor.color
                    )
                    .frame(width: 88, height: 88)
                    Text("Drag to turn the gradient").font(.headline)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                ForEach(BrowserSpaceBannerPattern.allCases, id: \.self) { pattern in
                    BrowserSpaceOptionCard(
                        title: pattern.titleKey,
                        isSelected: branding.themeMode == .banner && branding.bannerPattern == pattern,
                        tint: .accentColor,
                        select: {
                            branding.themeMode = .banner
                            branding.bannerPattern = pattern
                        }
                    ) {
                        BrowserSpaceBannerBackground(
                            branding: $branding.editorPreview {
                                $0.themeMode = .banner
                                $0.bannerPattern = pattern
                            }
                        )
                        .frame(height: 86)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
                BrowserSpaceOptionCard(
                    title: "Gradient", isSelected: branding.themeMode == .gradient,
                    tint: .accentColor, select: { branding.themeMode = .gradient }
                ) {
                    BrowserSpaceBannerBackground(branding: $branding.editorPreview { $0.themeMode = .gradient })
                        .frame(height: 86)
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }
}
