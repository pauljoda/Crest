import SwiftUI

struct BrowserPinnedExtensionActionButton: View {
    // MARK: - Static Variables

    private static let tileSize: CGFloat = 24
    private static let glyphSize: CGFloat = 16

    // MARK: - Variables

    let action: BrowserExtensionActionPresentation
    let perform: (BrowserExtensionPopupAnchor?) -> Void
    var prepare: () -> Void = {}
    var presentMenu: (BrowserExtensionPopupAnchor?) -> Void = { _ in }
    /// Runs the action as soon as the button is on screen to open its popup
    /// from, as when a Quick Window moves it out of its overflow to run it.
    var performsOnceAnchored = false

    @Environment(BrowserExtensionTileLiftState.self) private var tileLift: BrowserExtensionTileLiftState?
    @State private var isHovering = false
    @State private var popupAnchor: BrowserExtensionPopupAnchor?

    var body: some View {
        anchoredButton
            .onChange(of: [performsOnceAnchored, popupAnchor != nil], initial: true) { _, state in
                guard state.allSatisfy({ $0 }) else { return }
                performAction()
            }
            .background(
                .quaternary.opacity(isHovering ? 1 : 0),
                in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
            .onHover(perform: hoverChanged)
    }

    private var anchoredButton: some View {
        actionButton
            .frame(
                width: Self.tileSize,
                height: Self.tileSize
            )
            .background {
                BrowserExtensionPopupAnchorReader(
                    popupAnchor: $popupAnchor,
                    site: .tile(action.id)
                )
            }
            .overlay {
                BrowserExtensionContextMenuTrigger(presentMenu: presentMenu)
            }
    }

    private var actionButton: some View {
        Button(action: performAction) {
            Group {
                if action.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    BrowserExtensionActionArtwork(
                        action: action,
                        glyphSize: Self.glyphSize
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled || action.isLoading)
        .accessibilityLabel(action.displayName)
        .accessibilityValue(
            action.isLoading ? "Loading…" : ""
        )
        .accessibilityIdentifier("pinned-extension-action-\(action.id)")
        .help(Text(verbatim: action.displayName))
    }

    /// A tile a carried tile slides under is not one the person pointed at,
    /// so it neither lights up nor gets ready to run.
    private func hoverChanged(_ isHovering: Bool) {
        self.isHovering = isHovering && tileLift?.isCarrying != true
        guard self.isHovering, action.isEnabled, !action.isLoading else { return }
        prepare()
    }

    /// Runs the action, unless the click ends a drag that carried a tile.
    private func performAction() {
        guard tileLift?.suppressesActivation != true else { return }
        perform(popupAnchor)
    }
}
