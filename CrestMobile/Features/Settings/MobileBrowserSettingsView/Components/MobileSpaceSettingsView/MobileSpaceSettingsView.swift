import SwiftUI
import UIKit

struct MobileSpaceSettingsView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.browserSettingsSelectLiveSpace) private var liveSpaceSelection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selectedSpaceID: UUID?
    @State private var editorSection = BrowserSpaceEditorSection.appearance
    @State private var editingAppearanceSpace: SpaceModel?
    @State private var forgeStep = BrowserCrestStudioStep.shape
    @State private var pendingGroupChange: BrowserSpaceGroupChange?
    @State private var pendingDeletion: BrowserSpaceDeletionRequest?

    var body: some View {
        Group {
            if usesLiveSidebar {
                liveWorkspace
            } else {
                compactSettings
            }
        }
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
        .browserSpaceGroupChangeConfirmation($pendingGroupChange, browser: browser, spaceAccess: spaceAccess)
        .browserSpaceDeletionConfirmation(
            $pendingDeletion, browser: browser, spaceAccess: spaceAccess, dataDeleter: dataDeleter
        )
        .onDisappear { BrowserSpaceGroupNotices.shared.dismiss() }
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
    }

    private var compactSettings: some View {
        BrowserSettingsPane(.spaces) {
            MobileSpaceSelectionSection(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: { selectEditedSpace($0) }),
                addSubSpace: addSubSpace,
                requestGroupChange: { pendingGroupChange = $0 },
                requestDeletion: { pendingDeletion = $0 }
            )

            if let space, !browser.isPrivateBrowsing {
                Section {
                    groupCrestRow(for: space)
                }
            }

            if let space, canReveal(space) {
                MobileSpaceCustomizationSection(
                    space: space,
                    editAppearance: { editingAppearanceSpace = space }
                )

                detailSections(for: space)
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space,
                    accessController: spaceAccess,
                    detail: "Unlock this Space to see its settings."
                )
            }
        }
    }

    private var liveWorkspace: some View {
        VStack(spacing: 0) {
            MobileSpaceSettingsWorkspaceToolbar(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: { selectEditedSpace($0) }),
                section: $editorSection,
                addSubSpace: addSubSpace,
                requestGroupChange: { pendingGroupChange = $0 },
                requestDeletion: { pendingDeletion = $0 })
            if let space, !browser.isPrivateBrowsing {
                groupCrestRow(for: space)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .background(BrowserSettingsCanvas.card)
            }
            Divider()
            if BrowserSpaceGroupNotices.shared.current != nil {
                BrowserSpaceGroupNoticeLabel()
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, CrestSpacing.small)
                    .background(BrowserSettingsCanvas.card)
            }
            if let space {
                if canReveal(space) {
                    Group {
                        switch editorSection.kind {
                        case .appearance:
                            BrowserCrestForge(
                                branding: browser.spaceBrandingBinding(in: space),
                                symbol: browser.spaceSymbolBinding(in: space), step: $forgeStep,
                                name: browser.spaceNameBinding(in: space))
                        case .settings:
                            Form {
                                detailSections(for: space)
                            }
                        }
                    }
                    .id(space.id)
                } else {
                    BrowserSettingsPane(.spaces) {
                        BrowserSettingsPrivateSpaceAccessSection(
                            space: space, accessController: spaceAccess,
                            detail: "Unlock this Space to see its settings.")
                    }
                }
            } else {
                ContentUnavailableView("Select a Space", systemImage: "square.grid.2x2")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserSettingsCanvas.background)
    }

    /// The crests of `space`'s group, which pick the Space these settings
    /// edit, start a Sub-Space and, from each crest's menu, change the group.
    private func groupCrestRow(for space: SpaceModel) -> some View {
        BrowserSpaceGroupCrestRow(
            browser: browser, space: space, style: .touch, metrics: .touch, draggedSpaceID: .constant(nil),
            select: { selectEditedSpace($0) }, addSubSpace: addSubSpace,
            requestGroupChange: { pendingGroupChange = $0 }, requestDeletion: { pendingDeletion = $0 })
    }

    /// Starts a Sub-Space after `spaceID`, in its group, and edits it.
    private func addSubSpace(after spaceID: UUID) {
        guard browser.addSubSpace(after: spaceID) else { return }
        BrowserSpaceGroupNotices.formed()
        selectEditedSpace(browser.selectedSpaceID)
    }

    private func detailSections(for space: SpaceModel) -> some View {
        BrowserSpaceSettingsSections(
            browser: browser,
            space: space,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            dismissKeyboard: dismissKeyboard)
    }

    private func selectEditedSpace(_ id: UUID?) {
        selectedSpaceID = id
        if usesLiveSidebar, let id, id != browser.shownSpace?.id { liveSpaceSelection?.select(id) }
    }

    @ViewBuilder
    private func appearanceWorkspace(for requested: SpaceModel) -> some View {
        if let currentSpace = browser.spaceModel(requested.id),
            canReveal(currentSpace)
        {
            BrowserCrestForge(
                branding: browser.spaceBrandingBinding(in: currentSpace),
                symbol: browser.spaceSymbolBinding(in: currentSpace), step: $forgeStep,
                name: browser.spaceNameBinding(in: currentSpace), listsSteps: horizontalSizeClass == .compact)
        }
    }

    private var editedSpaceID: UUID? {
        usesLiveSidebar ? browser.selectedSpaceID : selectedSpaceID
    }

    private var space: SpaceModel? {
        guard let editedSpaceID else { return nil }
        return browser.spaceModel(editedSpaceID)
    }

    private func canReveal(_ space: SpaceModel) -> Bool {
        !spaceAccess.isLocked(space)
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
