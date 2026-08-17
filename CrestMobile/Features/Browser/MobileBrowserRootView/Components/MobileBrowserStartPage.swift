import SwiftUI

struct MobileBrowserStartPage: View {
    let space: BrowserSpace?
    let isPrivateBrowsing: Bool
    @Binding var address: String
    let focusRequest: Int
    let usesCommandPalette: Bool
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let isCommandPaletteObscured: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder
    var body: some View {
        MobileBrowserStartPageContent(
            space: space,
            isPrivateBrowsing: isPrivateBrowsing,
            focusRequest: focusRequest,
            usesCommandPalette: usesCommandPalette,
            isSourceAvailable: isSourceAvailable,
            selectTab: selectTab,
            openURL: openURL,
            isCommandPaletteObscured: isCommandPaletteObscured,
            headerColorScheme: startPageHeaderColorScheme
        )
        .onChange(of: usesCommandPalette, initial: true) { _, current in
            if !current {
                address = ""
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start-page-surface")
    }

    private var startPageHeaderColorScheme: ColorScheme {
        guard
            MobileStartPageAppearancePolicy.foregroundTone(
                usesCommandPalette: usesCommandPalette
            ) == .onBrand,
            let space
        else { return colorScheme }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }
}
