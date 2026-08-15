import SwiftUI

struct MobileSpaceSelectionSection: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: SpaceID?

    var body: some View {
        Section("Space") {
            Picker("Edit", selection: $selectedSpaceID) {
                ForEach(browser.session.spaces) { space in
                    BrowserSpaceIdentityLabel(space: space)
                        .tag(Optional(space.id))
                }
            }

            Button("Add Space", systemImage: "plus") {
                browser.addSpace()
                selectedSpaceID = browser.session.selectedSpaceID
            }
        }
    }
}

#Preview("Mobile Space Selection") {
    let fixture = MobileBrowserPreviewFixture()
    Form {
        MobileSpaceSelectionSection(
            browser: fixture.browser,
            selectedSpaceID: .constant(fixture.space.id)
        )
    }
}
