import SwiftUI
import UIKit

struct MobileSpaceSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selectedSpaceID: SpaceID?
    @State private var managedSearchEngineSpace: BrowserSpace?

    var body: some View {
        BrowserSettingsPane(.spaces) {
            MobileSpaceSelectionSection(
                browser: browser,
                selectedSpaceID: $selectedSpaceID
            )

            if let space, canReveal(space) {
                MobileSpaceCustomizationSection(
                    browser: browser,
                    space: space
                )

                // Touch takes the shared superset without downloads — the
                // system owns where a download lands here — and without the
                // Crest Passwords toggles, which this shell offers in its own
                // Passwords pane.
                BrowserSpaceSettingsSections(
                    browser: browser,
                    space: space,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    manageSearchEngines: {
                        managedSearchEngineSpace = space
                    },
                    dismissKeyboard: dismissKeyboard
                )
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: browser.liveSpace(space),
                    accessController: spaceAccess,
                    detail: "Unlock this Space before viewing its tab preview or changing its settings."
                )
            }
        }
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
        .sheet(item: $managedSearchEngineSpace) { space in
            BrowserSearchEngineManager(
                browser: browser,
                space: space,
                dismissKeyboard: dismissKeyboard
            )
        }
    }

    private var space: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    private func canReveal(_ space: BrowserSpace) -> Bool {
        BrowserSettingsPrivacyPolicy.canRevealSpaceData(
            in: browser.liveSpace(space),
            accessController: spaceAccess
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.endEditing(true)
            }
        }
    }
}
