import SwiftUI

/// Shared sections use an adaptive canvas in browser tabs and a grouped Form
/// in compact Settings sheets, without duplicating preference bindings.
///
/// A pane is built only out of ``BrowserSettingsSectionSlot``s, each naming a
/// section its page lists, so everything on the page is in its search index.
struct BrowserSettingsPane<Content: View>: View {
    @Environment(\.browserSettingsSectionOwner) private var outerOwner
    let destination: BrowserSettingsDestination
    let content: Content

    init(
        _ destination: BrowserSettingsDestination,
        @BrowserSettingsSectionsBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        BrowserPlatformSettingsPaneContainer(destination: destination) {
            content
        }
        // A Space page that shows a destination's pane for one Space lists
        // the sections itself.
        .environment(\.browserSettingsSectionOwner, outerOwner ?? destination.sections)
    }
}
