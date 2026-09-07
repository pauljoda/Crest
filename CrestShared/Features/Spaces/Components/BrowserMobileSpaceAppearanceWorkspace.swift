#if os(iOS)
    import SwiftUI

    /// Setup drafts and live Settings use the same touch editor and adaptive preview.
    struct BrowserMobileSpaceAppearanceWorkspace: View {
        @Binding var branding: BrowserSpaceBranding
        @Binding var symbol: String
        @Binding var name: String
        var space: BrowserSpace? = nil
        var spacePicker: BrowserSpaceCustomizationPicker? = nil
        var showsNameHint = false
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700 && horizontalSizeClass == .regular
                HStack(alignment: .top, spacing: wide ? 24 : 0) {
                    if wide {
                        preview(compact: false)
                            .frame(width: 260)
                            .frame(maxHeight: 580)
                            .padding(.leading, 24)
                            .padding(.vertical, 20)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !wide { preview(compact: true) }
                            BrowserSpaceBrandingEditor(
                                branding: $branding, symbol: $symbol,
                                compact: !wide, showsPreview: false, dense: true)
                        }
                        .padding(wide ? 24 : 20)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                        .id("mobile-space-appearance-top")
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollsSpaceAppearancePages(anchorID: "mobile-space-appearance-top")
                }
            }
            .background(BrowserOnboardingPalette.parchment)
            .foregroundStyle(BrowserOnboardingPalette.ink)
        }

        private func preview(compact: Bool) -> some View {
            BrowserSpaceAppearanceHero(
                branding: branding, symbol: symbol, name: name, compact: compact,
                space: space, editableName: $name, showsNameHint: showsNameHint, spacePicker: spacePicker)
        }
    }
#endif
