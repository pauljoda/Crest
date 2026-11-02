import SwiftUI

/// Crest's shared launcher, presented as an overlay, on the Start Page, or
/// grown out of an address field.
@MainActor
struct BrowserCommandPalette: View {
    let presentation: BrowserCommandPalettePresentation
    /// The window's command-surface namespace, in which an overlay palette
    /// grows out of its Space's address field. Absent where the palette
    /// appears in place.
    let morphNamespace: Namespace.ID?
    let overlayContentLeadingInset: CGFloat
    let overlayContentInsets: EdgeInsets?
    /// The frame of the address field a palette grows out of, in the space
    /// the palette is laid out in.
    let fieldFrame: CGRect?

    @State private var model: BrowserCommandPaletteModel

    init(
        browser: BrowserStore,
        space: SpaceModel?,
        selectedTabID: UUID?,
        initialQuery: String = "",
        commands: BrowserCommandPaletteCommandRegistry? = nil,
        offersRestingCommands: Bool = true,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool,
        dismiss: @escaping () -> Void,
        presentation: BrowserCommandPalettePresentation = .overlay,
        morphNamespace: Namespace.ID? = nil,
        overlayContentLeadingInset: CGFloat = 0,
        overlayContentInsets: EdgeInsets? = nil,
        fieldFrame: CGRect? = nil,
        destination: (any BrowserPaletteDestination)? = nil,
        openings: [BrowserCommandPaletteOpening] = [.here],
        readPasteboard: () -> String? = { nil }
    ) {
        self.presentation = presentation
        self.morphNamespace = morphNamespace
        self.overlayContentLeadingInset = overlayContentLeadingInset
        self.overlayContentInsets = overlayContentInsets
        self.fieldFrame = fieldFrame
        _model = State(
            initialValue: BrowserCommandPaletteModel(
                browser: browser,
                space: space,
                selectedTabID: selectedTabID,
                initialQuery: initialQuery,
                commands: commands,
                offersRestingCommands: offersRestingCommands,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                openURL: openURL,
                dismiss: dismiss,
                destination: destination,
                openings: openings,
                readPasteboard: readPasteboard
            ))
    }

    var body: some View {
        BrowserCommandPaletteContent(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            overlayContentLeadingInset: overlayContentLeadingInset,
            overlayContentInsets: overlayContentInsets,
            fieldFrame: fieldFrame
        )
        .onChange(of: model.isCompletionSourceAvailable) { _, available in
            if !available { model.invalidateURLCompletion() }
        }
        .onDisappear { model.invalidateURLCompletion() }
    }
}

#Preview("Command Palette — Overlay") {
    ZStack {
        CrestBrandTheme.canvas
        BrowserCommandPalette(
            browser: BrowserCommandPalettePreviewFixture.browser,
            space: BrowserCommandPalettePreviewFixture.space,
            selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
            initialQuery: "swift",
            commands: BrowserCommandPalettePreviewFixture.registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, _, _ in true },
            dismiss: {}
        )
    }
    .frame(width: 980, height: 720)
}

#Preview("Command Palette — Embedded") {
    BrowserCommandPalette(
        browser: BrowserCommandPalettePreviewFixture.browser,
        space: BrowserCommandPalettePreviewFixture.space,
        selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
        commands: BrowserCommandPalettePreviewFixture.registry,
        offersRestingCommands: false,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        openURL: { _, _, _ in true },
        dismiss: {},
        presentation: .embedded
    )
    .padding(CrestSpacing.large)
    .frame(width: 760)
}
