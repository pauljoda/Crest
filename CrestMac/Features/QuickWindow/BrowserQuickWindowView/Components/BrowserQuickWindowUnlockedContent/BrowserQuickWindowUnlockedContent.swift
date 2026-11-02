import SwiftUI

struct BrowserQuickWindowUnlockedContent: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void

    @State private var addressText: String
    @State private var isAddressEditing = false
    @State private var addressFocusRequest = 0
    /// The window's command-surface namespace, in which the palette grows out
    /// of the address field.
    @Namespace private var commandSurfaceNamespace

    @Environment(BrowserChromeState.self) private var chrome: BrowserChromeState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: BrowserQuickWindowModel,
        spaceAccess: BrowserSpaceAccessController,
        dismiss: @escaping () -> Void,
        openBrowserWindow: @escaping () -> Void
    ) {
        self.model = model
        self.spaceAccess = spaceAccess
        self.dismiss = dismiss
        self.openBrowserWindow = openBrowserWindow
        _addressText = State(
            initialValue: model.presentedRequest.initialURL?.absoluteString
                ?? ""
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            BrowserQuickWindowPageSurface(model: model)
                .padding(.top, BrowserQuickWindowLayout.toolbarHeight)
            BrowserQuickWindowToolbar(
                model: model,
                addressText: $addressText,
                isAddressEditing: $isAddressEditing,
                addressFocusRequest: addressFocusRequest,
                commandSurfaceNamespace: commandSurfaceNamespace,
                commandPaletteHandoff: commandPaletteHandoff,
                promote: promote
            )
        }
        .overlayPreferenceValue(BrowserQuickWindowCommandPaletteLayer.FieldAnchor.self) { anchor in
            if let chrome {
                GeometryReader { proxy in
                    BrowserQuickWindowCommandPaletteLayer(
                        model: model,
                        chrome: chrome,
                        fieldFrame: anchor.map { proxy[$0] },
                        morphNamespace: commandSurfaceNamespace,
                        openBrowserWindow: openBrowserWindow
                    )
                }
            }
        }
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: isPaletteShown
        )
        .modifier(
            BrowserQuickWindowActivityLifecycleModifier(
                model: model,
                spaceAccess: spaceAccess,
                dismiss: dismiss
            )
        )
        .modifier(
            BrowserQuickWindowPageObservationModifier(
                model: model,
                addressText: $addressText,
                isAddressEditing: isAddressEditing
            )
        )
        .task { await requestInitialAddressFocus() }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Quick Window using \(model.spaceModel?.settings.name ?? "Space")"
        )
    }

    private var isPaletteShown: Bool { chrome?.commandPaletteMode != nil && model.spaceModel != nil }

    /// Which of the address field and the palette holds their shared
    /// identity: the palette's glass grows out of the field's and shrinks
    /// back into it.
    private var commandPaletteHandoff: BrowserCommandPaletteHandoff {
        .resolve(
            isPaletteShown: isPaletteShown,
            isFieldOnScreen: true,
            animates: BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        )
    }

    /// An empty Quick Window opens its palette, as a new tab does, or
    /// without one selects its address field.
    private func requestInitialAddressFocus() async {
        guard model.presentedRequest.initialURL == nil else { return }
        try? await Task.sleep(
            for: BrowserQuickWindowLayout.initialAddressFocusDelay
        )
        if let chrome {
            chrome.presentCommandPalette()
        } else {
            addressFocusRequest &+= 1
        }
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard model.promote(to: assignment) else { return }
        openBrowserWindow()
        dismiss()
    }
}
