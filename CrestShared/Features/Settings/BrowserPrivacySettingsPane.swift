import SwiftUI

/// What a Space blocks, and what it has already been told about individual sites.
struct BrowserPrivacySettingsPane: View {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceAccess: BrowserSpaceAccessController
    let permissionCenter: BrowserSitePermissionCenter
    let contentBlockingErrorDescription: String?

    @State private var selectedSpaceID: SpaceID?
    @State private var confirmsReset = false

    var body: some View {
        BrowserSettingsPane(.privacy) {
            BrowserPrivacySpaceSection(
                selectedSpaceID: $selectedSpaceID,
                spaces: browser.session.spaces
            )

            if canRevealSelectedSpaceData {
                if let selectedSpaceID {
                    BrowserDataRetentionSettingsSection(
                        browser: browser,
                        downloadCenter: downloadCenter,
                        spaceID: selectedSpaceID
                    )
                }

                BrowserContentBlockingSettingsSection(
                    policy: contentBlockingPolicyBinding,
                    errorDescription: contentBlockingErrorDescription
                )

                BrowserSavedSitePermissionSection(
                    records: records,
                    permissionCenter: permissionCenter,
                    resetAll: { confirmsReset = true }
                )

                Section {
                    BrowserPlatformPrivacyScopeFootnote()
                }
            } else if let selectedSpace {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: selectedSpace,
                    accessController: spaceAccess,
                    detail:
                        "Unlock this Space before viewing site names, saved permissions, or content-blocking settings."
                )
            }
        }
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
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
            Text("Makes every site ask again in this Space")
        }
    }

    private var records: [BrowserSitePermissionRecord] {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return [] }
        return permissionCenter.records(in: selectedSpaceID)
    }

    private var selectedSpace: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    private var canRevealSelectedSpaceData: Bool {
        BrowserSettingsPrivacyPolicy.canRevealSpaceData(
            in: selectedSpace,
            accessController: spaceAccess
        )
    }

    private var contentBlockingPolicyBinding: Binding<BrowserContentBlockingPolicy> {
        browser.browsingPreferenceBinding(
            \.contentBlockingPolicy,
            in: selectedSpaceID,
            default: .balanced
        )
    }

    private func resetAll() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        permissionCenter.reset(spaceID: selectedSpaceID)
    }
}
