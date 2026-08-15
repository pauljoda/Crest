import SwiftUI

struct MobileBrowserStartPageStack: View {
    let space: BrowserSpace?
    let isPrivateBrowsing: Bool
    let focusRequest: Int
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let isCommandPaletteObscured: Bool
    let spacing: CGFloat
    let padding: CGFloat
    let maximumWidth: CGFloat
    let headerColorScheme: ColorScheme

    var body: some View {
        VStack(spacing: spacing) {
            MobileBrowserStartPageHeader(
                isPrivateBrowsing: isPrivateBrowsing,
                colorScheme: headerColorScheme
            )
            BrowserCommandPalette(
                space: space,
                selectedTabID: space?.selectedTabID,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                openURL: openURL,
                dismiss: {},
                presentation: .embedded
            )
            .id(
                BrowserCommandPalettePresentationIdentity(
                    focusRequest: focusRequest,
                    source: sourceAssignment
                )
            )
            .accessibilityIdentifier("start-page-command-palette")
            .accessibilityHidden(isCommandPaletteObscured)
        }
        .padding(padding)
        .frame(maxWidth: maximumWidth)
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID = space.selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(
            tabID: selectedTabID,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }
}

#Preview("Mobile Browser Start Page Stack") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserStartPageStack(
        space: fixture.space,
        isPrivateBrowsing: true,
        focusRequest: 0,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        openURL: { _, _ in true },
        isCommandPaletteObscured: false,
        spacing: MobileBrowserChromeLayout.compactStartPageSpacing,
        padding: MobileBrowserChromeLayout.compactStartPagePadding,
        maximumWidth: MobileBrowserChromeLayout.compactStartPageMaximumWidth,
        headerColorScheme: .dark
    )
}
