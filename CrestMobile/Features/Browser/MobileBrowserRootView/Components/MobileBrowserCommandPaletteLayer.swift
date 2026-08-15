import SwiftUI

struct MobileBrowserCommandPaletteLayer: View {
    let mode: BrowserCommandPaletteMode?
    let space: BrowserSpace?
    let selectedTabID: TabID?
    let otherSpaces: [BrowserSpace]
    let commands: BrowserCommandPaletteCommandRegistry
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let selectTabInSpace:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let openURL:
        (
            BrowserTabRuntimeAssignment,
            URL,
            BrowserCommandPaletteMode
        ) -> Bool
    let dismiss: () -> Void
    let morphNamespace: Namespace.ID

    var body: some View {
        if let mode, let sourceAssignment,
            isSourceAvailable(sourceAssignment)
        {
            BrowserCommandPalette(
                space: space,
                selectedTabID: selectedTabID,
                initialQuery: mode.initialQuery,
                otherSpaces: otherSpaces,
                commands: commands,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                selectTabInSpace: selectTabInSpace,
                openURL: { source, url in openURL(source, url, mode) },
                dismiss: dismiss,
                morphNamespace: morphNamespace,
                morphID: "crest-address-command-\(space?.id.id.uuidString ?? "none")"
            )
            .id(
                BrowserCommandPalettePresentationIdentity(
                    mode: mode,
                    source: sourceAssignment,
                    otherSpaces: otherSpaces
                )
            )
            .transition(.browserCommandPaletteOverlay)
            .zIndex(MobileBrowserRootLayout.paletteLayer)
        }
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

#Preview("Mobile Browser Command Palette Layer") {
    @Previewable @Namespace var morphNamespace

    MobileBrowserCommandPaletteLayer(
        mode: .newTab,
        space: BrowserCommandPalettePreviewFixture.currentSpace,
        selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
        otherSpaces: [BrowserCommandPalettePreviewFixture.otherSpace],
        commands: BrowserCommandPalettePreviewFixture.registry,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        selectTabInSpace: { _, _ in true },
        openURL: { _, _, _ in true },
        dismiss: {},
        morphNamespace: morphNamespace
    )
}
