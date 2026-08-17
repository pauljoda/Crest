import SwiftUI

struct BrowserPrivacySpaceSection: View {
    @Binding var selectedSpaceID: SpaceID?
    let spaces: [BrowserSpace]

    var body: some View {
        Section("Space") {
            CrestSpaceMenuPicker(
                "Permissions for",
                selection: $selectedSpaceID,
                spaces: CrestSpaceIdentity.list(spaces)
            )
        }
    }
}
