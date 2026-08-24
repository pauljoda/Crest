import SwiftUI

/// The sidebar's address field, on every shell.
///
/// The field owns the address, the editing ring, the loading wash, and the
/// matched-geometry anchor that grows it into the command palette. What it does
/// not own are the two controls a live site contributes and the menu a compact
/// shell hangs off the field: those reach into a page layer that is the
/// platform's own, so they arrive as slots the field decides *when* to draw
/// rather than views it knows how to build.
struct BrowserSidebarAddressField<
    LeadingAccessory: View,
    TrailingAccessory: View,
    FieldContextMenu: View
>: View {
    private let configuration: BrowserSidebarAddressFieldConfiguration
    private let leadingAccessory: LeadingAccessory
    private let trailingAccessory: TrailingAccessory
    private let fieldContextMenu: FieldContextMenu

    init(
        configuration: BrowserSidebarAddressFieldConfiguration,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory = { EmptyView() },
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = {
            EmptyView()
        },
        @ViewBuilder fieldContextMenu: () -> FieldContextMenu = { EmptyView() }
    ) {
        self.configuration = configuration
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
        self.fieldContextMenu = fieldContextMenu()
    }

    @ViewBuilder
    var body: some View {
        if hasFieldContextMenu {
            field.contextMenu {
                fieldContextMenu
                    .crestMenuActionLabelStyle()
            }
        } else {
            field
        }
    }

    private var field: some View {
        BrowserSidebarAddressFieldContent(configuration: configuration) {
            leadingAccessory
        } trailingAccessory: {
            trailingAccessory
        }
        .browserAddressFieldSurface(
            metrics: configuration.metrics,
            progress: configuration.progress,
            isLoading: configuration.isLoading,
            isEditing: configuration.isEditing.wrappedValue
        )
        .matchedGeometryEffect(
            id: configuration.morphID,
            in: configuration.morphNamespace,
            properties: .frame,
            anchor: .center,
            isSource: true
        )
    }

    /// Whether this field was given a menu at all.
    ///
    /// A blanket `.contextMenu` holding nothing is not the same as no context
    /// menu: it replaces whatever the platform's own text field would have
    /// offered — copy, paste, look up — with an empty one. A shell that has no
    /// menu to add keeps the system's.
    private var hasFieldContextMenu: Bool {
        FieldContextMenu.self != EmptyView.self
    }
}
