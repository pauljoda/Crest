import SwiftUI

/// What a Space keeps and what it has already been told about individual
/// sites. Ad blocking holds for every Space, so it has a pane of its own.
struct BrowserPrivacySettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let permissionCenter: BrowserSitePermissionCenter
    /// The one Space whose privacy the pane shows, with its lock, or nil to
    /// pick one.
    var fixedSpaceID: UUID? = nil

    @State private var pickedSpaceID: UUID?
    private var selectedSpaceID: UUID? { fixedSpaceID ?? pickedSpaceID }
    private var selectedSpaceBinding: Binding<UUID?> {
        Binding(get: { selectedSpaceID }, set: { if fixedSpaceID == nil { pickedSpaceID = $0 } })
    }
    @State private var confirmsReset = false
    /// The sites that keep data in the shown Space, listed once it shows.
    @State private var websiteData: BrowserWebsiteDataList?

    var body: some View {
        BrowserSettingsPane(.privacy) {
            if fixedSpaceID == nil {
                BrowserPrivacySpaceSection(
                    selectedSpaceID: selectedSpaceBinding,
                    spaces: browser.spaceModels
                )
            }

            if canRevealSelectedSpaceData {
                if fixedSpaceID != nil, let selectedSpace {
                    BrowserSpaceAccessPolicySection(browser: browser, space: selectedSpace, spaceAccess: spaceAccess)
                }

                if let selectedSpaceID {
                    BrowserDataRetentionSettingsSection(
                        browser: browser,
                        spaceID: selectedSpaceID
                    )
                }

                if browser.core.state.offers(.permissions) {
                    BrowserSavedSitePermissionSection(
                        records: records,
                        permissionCenter: permissionCenter,
                        resetAll: { confirmsReset = true }
                    )
                }

                if let selectedSpace {
                    BrowserWebsiteDataSection(
                        list: websiteData?.profileID == selectedSpace.profileID ? websiteData : nil,
                        spaceName: selectedSpace.settings.name,
                        isSharedByGroup: browser.groupMembers(of: selectedSpace).count > 1)
                    BrowserClearBrowsingDataSection(browser: browser, space: selectedSpace) {
                        Task { await websiteData?.read() }
                    }
                }
                BrowserSpaceGroupSharingNote(browser: browser, spaceID: selectedSpaceID)
            } else if let selectedSpace {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: selectedSpace,
                    accessController: spaceAccess,
                    detail: "Unlock this Space to see its privacy settings."
                )
            }
        }
        .crestRepairsSpaceSelection(selectedSpaceBinding, in: browser)
        .task(id: canRevealSelectedSpaceData ? selectedSpace?.profileID : nil) {
            guard canRevealSelectedSpaceData, let selectedSpace else {
                websiteData = nil
                return
            }
            let list = BrowserWebsiteDataList(
                core: browser.core, profileID: selectedSpace.profileID, ephemeral: browser.isPrivateBrowsing)
            websiteData = list
            await list.read()
        }
        .onChange(of: canRevealSelectedSpaceData) { _, canReveal in
            if !canReveal {
                confirmsReset = false
            }
        }
        .confirmationDialog(
            "Reset All",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive, action: resetAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            if selectedSpace.map({ browser.groupMembers(of: $0).count > 1 }) == true {
                Text("Makes every site ask again in this Space and the others of its group")
            } else {
                Text("Makes every site ask again in this Space")
            }
        }
    }

    private var records: [SitePermissionRecordState] {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return [] }
        return permissionCenter.records(in: selectedSpaceID)
    }

    private var selectedSpace: SpaceModel? {
        guard let selectedSpaceID else { return nil }
        return browser.spaceModel(selectedSpaceID)
    }

    private var canRevealSelectedSpaceData: Bool {
        guard let selectedSpace else { return false }
        return !spaceAccess.isLocked(selectedSpace)
    }

    private func resetAll() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        permissionCenter.reset(spaceID: selectedSpaceID)
    }
}
