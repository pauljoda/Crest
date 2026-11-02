import SwiftUI

/// The pinned extension actions that do not fit a Quick Window's toolbar,
/// behind one button that drops them down as the same buttons in a column.
struct BrowserPinnedExtensionOverflowButton: View {
    // MARK: - Static Variables

    private static let spacing: CGFloat = 2

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let prepare: (BrowserExtensionActionPresentation) -> Void
    /// Moves a chosen action out to the toolbar to run there, answering
    /// whether it could.
    let choose: (BrowserExtensionActionPresentation) -> Bool
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void

    @State private var isPresented = false
    @State private var popupAnchor: BrowserExtensionPopupAnchor?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "chevron.forward.2")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
        .background { BrowserExtensionPopupAnchorReader(popupAnchor: $popupAnchor) }
        .accessibilityLabel("More Pinned Extensions")
        .help("More Pinned Extensions")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: Self.spacing) {
                ForEach(actions) { action in
                    BrowserPinnedExtensionActionButton(
                        action: action,
                        perform: { _ in run(action) },
                        prepare: { prepare(action) }
                    )
                }
            }
            .padding(CrestSpacing.small)
            .crestFlyoutStyle()
        }
    }

    // MARK: - Actions - Extensions

    /// Closes the overflow and runs `action` from the toolbar, or from this
    /// button when the toolbar has no place for it: a popup anchored inside
    /// the overflow would close with it.
    private func run(_ action: BrowserExtensionActionPresentation) {
        isPresented = false
        guard !choose(action) else { return }
        let anchor = popupAnchor
        DispatchQueue.main.async { perform(action, anchor) }
    }
}
