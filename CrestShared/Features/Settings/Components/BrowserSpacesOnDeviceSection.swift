import SwiftUI

/// Which Spaces of the person's own session this device shows, one switch
/// each. A hidden Space keeps syncing; only this device leaves it out of its
/// windows, and its settings page still opens here without moving one.
struct BrowserSpacesOnDeviceSection: View {
    let browser: BrowserStore

    var body: some View {
        if browser.offersSpaceVisibility {
            Section {
                ForEach(spaces) { space in
                    Toggle(isOn: browser.spaceVisibilityBinding(for: space)) {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                    .disabled(!browser.canChangeSpaceVisibility(of: space.id))
                    .accessibilityIdentifier("space-shows-on-device-\(space.id.uuidString)")
                }
            } header: {
                Text("Spaces on This Device")
            } footer: {
                CrestFormFootnote(
                    "Hidden Spaces keep syncing with your other devices. The Space you're using can't be hidden.")
            }
        }
    }

    /// Every Space the session keeps, hidden ones included, in its order.
    private var spaces: [SpaceModel] {
        browser.spaceModels.filter { !browser.isDeleting($0.id) }
    }
}

#if DEBUG
    #Preview("One Space hidden") {
        @Previewable @State var browser = BrowserStore(seed: .preview)
        Form { BrowserSpacesOnDeviceSection(browser: browser) }
            .crestSettingsForm().frame(width: 420, height: 220)
            .task { browser.showSpaceOnDevice(SessionState.Seed.preview.spaces[1].id, shown: false) }
    }
#endif
