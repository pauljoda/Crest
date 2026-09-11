import SwiftUI
import UIKit

struct MobileSpaceSettingsView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.browserSettingsSelectLiveSpace) private var liveSpaceSelection
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selectedSpaceID: SpaceID?
    @State private var editorSection = BrowserSpaceEditorSection.appearance
    @State private var managedSearchEngineSpace: BrowserSpace?
    @State private var editingAppearanceSpace: BrowserSpace?

    var body: some View {
        Group {
            if usesLiveSidebar {
                liveWorkspace
            } else {
                compactSettings
            }
        }
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
        .fullScreenCover(item: $editingAppearanceSpace) { requested in
            NavigationStack {
                appearanceWorkspace(for: requested)
                    .navigationTitle("Space appearance")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingAppearanceSpace = nil }
                        }
                    }
            }
        }
        .sheet(item: $managedSearchEngineSpace) { space in
            BrowserSearchEngineManager(
                browser: browser, space: space, dismissKeyboard: dismissKeyboard)
        }
    }

    private var compactSettings: some View {
        BrowserSettingsPane(.spaces) {
            MobileSpaceSelectionSection(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: selectEditedSpace)
            )

            if let space, canReveal(space) {
                MobileSpaceCustomizationSection(
                    browser: browser,
                    space: space,
                    editAppearance: { editingAppearanceSpace = space }
                )

                detailSections(for: space)
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: browser.liveSpace(space),
                    accessController: spaceAccess,
                    detail: "Unlock this Space before viewing its tab preview or changing its settings."
                )
            }
        }
    }

    private var liveWorkspace: some View {
        VStack(spacing: 0) {
            MobileSpaceSettingsWorkspaceToolbar(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: selectEditedSpace),
                section: $editorSection)
            Divider()
            if let space {
                if canReveal(space) {
                    Group {
                        switch editorSection {
                        case .appearance:
                            BrowserCrestStudioWorkspace(
                                branding: browser.spaceBrandingBinding(in: space),
                                symbol: browser.spaceIdentityBinding(\.symbol, in: space),
                                name: browser.spaceIdentityBinding(\.name, in: space))
                        case .settings:
                            ScrollView {
                                BrowserSettingsSectionGrid {
                                    detailSections(for: space)
                                }
                                .padding(24)
                            }
                        }
                    }
                    .id(space.id)
                } else {
                    BrowserSettingsPane(.spaces) {
                        BrowserSettingsPrivateSpaceAccessSection(
                            space: browser.liveSpace(space), accessController: spaceAccess,
                            detail: "Unlock this Space before viewing its tab preview or changing its settings.")
                    }
                }
            } else {
                ContentUnavailableView("Select a Space", systemImage: "square.grid.2x2")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserSettingsCanvas.background)
    }

    private func detailSections(for space: BrowserSpace) -> some View {
        BrowserSpaceSettingsSections(
            browser: browser,
            space: space,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            manageSearchEngines: { managedSearchEngineSpace = space },
            dismissKeyboard: dismissKeyboard)
    }

    private func selectEditedSpace(_ id: SpaceID?) {
        selectedSpaceID = id
        if usesLiveSidebar, let id, id != browser.selectedSpace?.id { liveSpaceSelection?.select(id) }
    }

    @ViewBuilder
    private func appearanceWorkspace(for requested: BrowserSpace) -> some View {
        if let currentSpace = browser.session.space(id: requested.id),
            canReveal(currentSpace)
        {
            BrowserMobileSpaceAppearanceWorkspace(
                branding: browser.spaceBrandingBinding(in: currentSpace),
                symbol: browser.spaceIdentityBinding(\.symbol, in: currentSpace),
                name: browser.spaceIdentityBinding(\.name, in: currentSpace), space: currentSpace)
        }
    }

    private var editedSpaceID: SpaceID? {
        usesLiveSidebar ? browser.session.selectedSpaceID : selectedSpaceID
    }

    private var space: BrowserSpace? {
        guard let editedSpaceID else { return nil }
        return browser.session.space(id: editedSpaceID)
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
