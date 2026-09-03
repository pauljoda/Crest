import SwiftUI

/// Crest's shared launcher, presented either as an overlay or on the Start Page.
@MainActor
struct BrowserCommandPalette: View {
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let morphID: String?
    let overlayContentLeadingInset: CGFloat

    @State private var model: BrowserCommandPaletteModel

    init(
        space: BrowserSpace?,
        selectedTabID: TabID?,
        initialQuery: String = "",
        commands: BrowserCommandPaletteCommandRegistry? = nil,
        isPrivateBrowsing: Bool = false,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL) -> Bool,
        dismiss: @escaping () -> Void,
        presentation: BrowserCommandPalettePresentation = .overlay,
        morphNamespace: Namespace.ID? = nil,
        morphID: String? = nil,
        overlayContentLeadingInset: CGFloat = 0
    ) {
        self.presentation = presentation
        self.morphNamespace = morphNamespace
        self.morphID = morphID
        self.overlayContentLeadingInset = overlayContentLeadingInset
        _model = State(
            initialValue: BrowserCommandPaletteModel(
                space: space,
                selectedTabID: selectedTabID,
                initialQuery: initialQuery,
                commands: commands,
                isPrivateBrowsing: isPrivateBrowsing,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                openURL: openURL,
                dismiss: dismiss
            ))
    }

    var body: some View {
        BrowserCommandPaletteContent(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            morphID: morphID,
            overlayContentLeadingInset: overlayContentLeadingInset
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
            commands: BrowserCommandPalettePreviewFixture.registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
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
        commands: BrowserCommandPalettePreviewFixture.registry,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        openURL: { _, _ in true },
        dismiss: {},
        presentation: .embedded
    )
    .padding(CrestSpacing.large)
    .frame(width: 760)
}
