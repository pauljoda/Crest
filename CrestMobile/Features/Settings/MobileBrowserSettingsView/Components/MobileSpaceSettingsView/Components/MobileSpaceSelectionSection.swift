import SwiftUI

struct MobileSpaceSelectionSection: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: SpaceID?

    var body: some View {
        Section("Space", systemImage: "square.grid.2x2") {
            Picker("Edit", selection: $selectedSpaceID) {
                ForEach(browser.session.spaces) { space in
                    BrowserSpaceIdentityLabel(space: space)
                        .tag(Optional(space.id))
                }
            }

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
                BrowserSpaceAddButton {
                    browser.addSpace()
                    selectedSpaceID = browser.session.selectedSpaceID
                }
            }
        }
    }
}
