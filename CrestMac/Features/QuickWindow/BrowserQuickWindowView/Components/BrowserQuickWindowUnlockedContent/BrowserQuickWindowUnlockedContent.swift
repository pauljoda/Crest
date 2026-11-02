import SwiftUI

struct BrowserQuickWindowUnlockedContent: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void

    @State private var addressText: String
    @State private var isAddressEditing = false
    @State private var addressFocusRequest = 0

    @Environment(BrowserChromeState.self) private var chrome: BrowserChromeState?

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
                promote: promote
            )
        }
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
        .onChange(of: chrome?.commandPaletteMode) { _, mode in
            // A Quick Window has no command bar: Open Location focuses its
            // own address field instead.
            guard mode != nil else { return }
            chrome?.dismissCommandPalette()
            addressFocusRequest &+= 1
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Quick Window using \(model.spaceModel?.settings.name ?? "Space")"
        )
    }

    private func requestInitialAddressFocus() async {
        guard model.presentedRequest.initialURL == nil else { return }
        try? await Task.sleep(
            for: BrowserQuickWindowLayout.initialAddressFocusDelay
        )
        addressFocusRequest &+= 1
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard model.promote(to: assignment) else { return }
        openBrowserWindow()
        dismiss()
    }
}
