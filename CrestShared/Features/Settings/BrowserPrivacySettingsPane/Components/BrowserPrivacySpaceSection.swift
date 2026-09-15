import SwiftUI

struct BrowserPrivacySpaceSection: View {
    @Binding var selectedSpaceID: SpaceID?
    let spaces: [BrowserSpace]

    var body: some View {
        Section("Space", systemImage: "square.grid.2x2") {
            CrestSpaceMenuPicker(
                "Permissions for",
                selection: $selectedSpaceID,
                spaces: CrestSpaceIdentity.list(spaces)
            )
        }
    }
}

#if DEBUG
    #Preview("Space selection") {
        @Previewable @State var selection: SpaceID? = BrowserSession.preview.selectedSpaceID
        Form { BrowserPrivacySpaceSection(selectedSpaceID: $selection, spaces: BrowserSession.preview.spaces) }
            .crestSettingsForm().frame(width: 420, height: 220)
    }
#endif
