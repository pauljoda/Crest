import SwiftUI

struct MobileSpaceSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selectedSpaceID: SpaceID?
    @State private var updatingAccessPolicy = false

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
                MobileSpaceBrowsingSection(browser: browser, space: space)
                MobilePrivateSpaceSettingsSection(
                    requiresAuthentication: requiresAuthentication(in: space),
                    isUpdating: updatingAccessPolicy
                )
                BrowserSpaceDeletionSection(
                    browser: browser,
                    spaceID: space.id,
                    dataDeleter: dataDeleter
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

    private func requiresAuthentication(in space: BrowserSpace) -> Binding<Bool> {
        Binding {
            browser.liveSpace(space).accessPolicy.requiresAuthentication
        } set: { isRequired in
            Task { await updateAccessPolicy(isRequired: isRequired, in: space) }
        }
    }

    private func updateAccessPolicy(
        isRequired: Bool,
        in space: BrowserSpace
    ) async {
        updatingAccessPolicy = true
        defer { updatingAccessPolicy = false }
        let currentSpace = browser.liveSpace(space)

        if !isRequired {
            guard await spaceAccess.unlock(currentSpace) else { return }
        }
        browser.updateSpaceAccessPolicy(
            isRequired ? .deviceOwnerAuthentication : .open,
            in: space.id
        )
        if isRequired {
            spaceAccess.lock(space.id)
        }
    }
}
