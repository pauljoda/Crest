import SwiftUI

struct BrowserStartPageCommandPalette: View {
    let space: BrowserSpace?
    let selectedTabID: TabID?
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let promotionNamespace: Namespace.ID
    let promotionID: String
    let isObscured: Bool
    let reduceMotion: Bool

    var body: some View {
        promotedPalette
            .accessibilityIdentifier("start-page-command-palette")
            .accessibilityHidden(isObscured)
    }

    @ViewBuilder
    private var promotedPalette: some View {
        if reduceMotion {
            palette
        } else {
            palette.matchedGeometryEffect(
                id: promotionID,
                in: promotionNamespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        }
    }

    private var palette: some View {
        BrowserCommandPalette(
            space: space,
            selectedTabID: selectedTabID,
            isSourceAvailable: isSourceAvailable,
            selectTab: selectTab,
            openURL: openURL,
            dismiss: {},
            presentation: .embedded
        )
        .id(
            BrowserCommandPalettePresentationIdentity(
                source: sourceAssignment
            )
        )
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space, let selectedTabID else { return nil }
        return BrowserTabRuntimeAssignment(
            tabID: selectedTabID,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }
}

#Preview("Start Page Command Palette") {
    @Previewable @Namespace var promotionNamespace
    BrowserStartPageCommandPalette(
        space: BrowserDetailPreviewFixture.space,
        selectedTabID: BrowserDetailPreviewFixture.tabID,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        openURL: { _, _ in true },
        promotionNamespace: promotionNamespace,
        promotionID: "start-page-command-palette-preview",
        isObscured: false,
        reduceMotion: false
    )
    .frame(width: 720, height: 420)
}
