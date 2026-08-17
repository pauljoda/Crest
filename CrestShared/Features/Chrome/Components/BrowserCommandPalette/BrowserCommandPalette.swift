import SwiftUI

/// Crest's shared launcher, presented either as an overlay or on the Start Page.
@MainActor
struct BrowserCommandPalette: View {
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?

    @State private var model: BrowserCommandPaletteModel

    init(
        space: BrowserSpace?,
        selectedTabID: TabID?,
        initialQuery: String = "",
        otherSpaces: [BrowserSpace] = [],
        commands: BrowserCommandPaletteCommandRegistry? = nil,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        selectTabInSpace: (
            (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool
        )? = nil,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL) -> Bool,
        dismiss: @escaping () -> Void,
        presentation: BrowserCommandPalettePresentation = .overlay,
        morphNamespace: Namespace.ID? = nil,
        morphID: String? = nil
    ) {
        self.presentation = presentation
        self.morphNamespace = morphNamespace
        self.morphID = morphID
        _model = State(
            initialValue: BrowserCommandPaletteModel(
                space: space,
                selectedTabID: selectedTabID,
                initialQuery: initialQuery,
                otherSpaces: otherSpaces,
                commands: commands,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                selectTabInSpace: selectTabInSpace,
                openURL: openURL,
                dismiss: dismiss
            ))
    }

    var body: some View {
        BrowserCommandPaletteContent(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            morphID: morphID
        )
    }
}

#Preview("Command Palette — Overlay") {
    ZStack {
        CrestBrandTheme.canvas
        BrowserCommandPalette(
            space: BrowserCommandPalettePreviewFixture.currentSpace,
            selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
            initialQuery: "swift",
            otherSpaces: [BrowserCommandPalettePreviewFixture.otherSpace],
            commands: BrowserCommandPalettePreviewFixture.registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            selectTabInSpace: { _, _ in true },
            openURL: { _, _ in true },
            dismiss: {}
        )
    }
    .frame(width: 980, height: 720)
}

#Preview("Command Palette — Embedded") {
    BrowserCommandPalette(
        space: BrowserCommandPalettePreviewFixture.currentSpace,
        selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
        otherSpaces: [BrowserCommandPalettePreviewFixture.otherSpace],
        commands: BrowserCommandPalettePreviewFixture.registry,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        selectTabInSpace: { _, _ in true },
        openURL: { _, _ in true },
        dismiss: {},
        presentation: .embedded
    )
    .padding(CrestSpacing.large)
    .frame(width: 760)
}
