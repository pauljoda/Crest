import SwiftUI

struct MobileBrowserStartPageContent: View {
    let space: BrowserSpace?
    let isPrivateBrowsing: Bool
    let focusRequest: Int
    let usesCommandPalette: Bool
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let isCommandPaletteObscured: Bool
    let headerColorScheme: ColorScheme

    var body: some View {
        ZStack {
            MobileBrowserStartPageBackground(
                space: space,
                usesCommandPalette: usesCommandPalette
            )
            if usesCommandPalette {
                stack(
                    spacing: MobileBrowserChromeLayout.regularStartPageSpacing,
                    padding: MobileBrowserChromeLayout.regularStartPagePadding,
                    maximumWidth: MobileBrowserChromeLayout.regularStartPageMaximumWidth
                )
            } else {
                ScrollView {
                    stack(
                        spacing: MobileBrowserChromeLayout.compactStartPageSpacing,
                        padding: MobileBrowserChromeLayout.compactStartPagePadding,
                        maximumWidth: MobileBrowserChromeLayout.compactStartPageMaximumWidth
                    )
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func stack(
        spacing: CGFloat,
        padding: CGFloat,
        maximumWidth: CGFloat
    ) -> some View {
        MobileBrowserStartPageStack(
            space: space,
            isPrivateBrowsing: isPrivateBrowsing,
            focusRequest: focusRequest,
            isSourceAvailable: isSourceAvailable,
            selectTab: selectTab,
            openURL: openURL,
            isCommandPaletteObscured: isCommandPaletteObscured,
            spacing: spacing,
            padding: padding,
            maximumWidth: maximumWidth,
            headerColorScheme: headerColorScheme
        )
    }
}
