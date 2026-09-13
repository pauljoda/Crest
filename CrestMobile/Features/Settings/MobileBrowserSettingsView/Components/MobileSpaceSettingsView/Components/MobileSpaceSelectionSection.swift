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

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
            }

            Button("New Space", systemImage: "plus") {
                browser.addSpace()
                selectedSpaceID = browser.session.selectedSpaceID
            }
            .accessibilityIdentifier("space-settings-add")
        }
    }
}
