import SwiftUI

/// Which WebExtensions a Space has loaded, and how each one is doing.
struct BrowserExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let extensionControllerPool: BrowserExtensionControllerPool
    var requestedSpaceID: SpaceID? = nil
    var requestRevision = 0

    @State private var selectedSpaceID: SpaceID?

    var body: some View {
        BrowserSettingsPane(.extensions) {
            Section("Space") {
                CrestSpaceMenuPicker(
                    "Manage extensions for",
                    selection: $selectedSpaceID,
                    spaces: CrestSpaceIdentity.list(browser.session.spaces)
                )
            }

            if let space, canRevealSelectedSpaceData {
                BrowserExtensionsView(
                    space: space,
                    extensionControllerPool: extensionControllerPool
                )
                .id(space.id)
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space,
                    accessController: spaceAccess,
                    detail: "Unlock this Space before viewing or changing its installed extensions."
                )
            }
        }
        .onAppear(perform: repairSelection)
        .onChange(of: browser.session.spaces.map(\.id)) {
            repairSelection()
        }
        .onChange(of: requestRevision, initial: true) { _, revision in
            guard revision > 0,
                let requestedSpaceID,
                browser.session.space(id: requestedSpaceID) != nil
            else {
                return
            }
            selectedSpaceID = requestedSpaceID
        }
    }

    private var space: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    private var canRevealSelectedSpaceData: Bool {
        BrowserSettingsPrivacyPolicy.canRevealSpaceData(
            in: space,
            accessController: spaceAccess
        )
    }

    private func repairSelection() {
        if let selectedSpaceID,
            browser.session.space(id: selectedSpaceID) != nil
        {
            return
        }
        selectedSpaceID = browser.session.selectedSpaceID
    }
}

#Preview("Extension Settings") {
    BrowserExtensionSettingsPane(
        browser: BrowserExtensionSettingsPreviewFixture.linkSettings.browser,
        spaceAccess:
            BrowserExtensionSettingsPreviewFixture.linkSettings.spaceAccess,
        extensionControllerPool:
            BrowserExtensionSettingsPreviewFixture.extensionControllerPool
    )
    .frame(width: 680, height: 720)
}
