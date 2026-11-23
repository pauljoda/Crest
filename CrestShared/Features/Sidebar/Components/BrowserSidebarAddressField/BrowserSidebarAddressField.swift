import SwiftUI

/// The sidebar's address field, on every shell.
///
/// The field owns the address, the editing ring, the loading wash, and the
/// matched-geometry anchors that turn it into the command palette and the
/// utility search toolbar. What it does not own are the two controls a live
/// site contributes: those reach into a page layer that is the platform's own,
/// so they arrive as slots the field decides *when* to draw rather than views
/// it knows how to build. A long press keeps the text field's own menu.
struct BrowserSidebarAddressField<LeadingAccessory: View, TrailingAccessory: View>: View {
    // MARK: - Variables

    private let configuration: BrowserSidebarAddressFieldConfiguration
    private let leadingAccessory: LeadingAccessory
    private let trailingAccessory: TrailingAccessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var handoffAnimation: Animation? {
        configuration.commandPaletteHandoff.fieldAnimation.unlessReducingMotion(reduceMotion)
    }

    // MARK: - Initializers

    init(
        configuration: BrowserSidebarAddressFieldConfiguration,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory = { EmptyView() },
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = {
            EmptyView()
        }
    ) {
        self.configuration = configuration
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        BrowserSidebarAddressFieldContent(configuration: configuration) {
            leadingAccessory
        } trailingAccessory: {
            trailingAccessory
        }
        .browserAddressFieldSurface(
            metrics: configuration.metrics,
            progress: configuration.progress,
            isLoading: configuration.isLoading,
            isEditing: configuration.isEditing.wrappedValue,
            branding: configuration.branding,
            activate: configuration.surfaceActivation
        )
        .matchedGeometryEffect(
            id: BrowserCommandSurfaceMorph.utilitySearch(
                spaceID: configuration.spaceID
            ),
            in: configuration.morphNamespace,
            properties: .frame,
            anchor: .center,
            isSource: true
        )
        .animation(handoffAnimation) {
            $0.opacity(configuration.commandPaletteHandoff.fieldOpacity)
        }
        .background { commandPaletteAnchor }
    }

    /// The field's frame, carrying the palette's identity while the field
    /// holds it.
    ///
    /// A clear stand-in rather than the field itself: letting go of the
    /// identity inserts and removes only the stand-in, never the field and
    /// whatever it is showing or editing. Removing it in the transaction that
    /// inserts the palette is what grows the palette out of this frame.
    @ViewBuilder
    private var commandPaletteAnchor: some View {
        if configuration.commandPaletteHandoff.fieldHoldsMorph {
            Color.clear.matchedGeometryEffect(
                id: BrowserCommandSurfaceMorph.commandPalette(
                    spaceID: configuration.spaceID
                ),
                in: configuration.morphNamespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        }
    }
}
