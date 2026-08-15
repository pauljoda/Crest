import SwiftUI

struct BrowserSidebar: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let utilityPresentation: BrowserUtilityPresentationState
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState

    @Environment(\.openWindow) private var openWindow
    @State private var pendingPageSelection: BrowserSpaceRuntimeAssignment?
    @State private var utilitySearchText = ""
    @State private var utilityFilter = BrowserUtilityListFilter.all
    @State private var clearHistoryConfirmation: BrowserSidebarClearHistoryConfirmation?

    var body: some View {
        if browser.session.spaces.isEmpty {
            ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2")
        } else {
            BrowserSidebarLoadedContent(
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                address: $address,
                isAddressEditing: $isAddressEditing,
                addressFocusRequest: addressFocusRequest,
                activateAddress: activateAddress,
                submitAddress: submitAddress,
                openNewTab: openNewTab,
                sidebarToggleAction: sidebarToggleAction,
                toggleSidebar: toggleSidebar,
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace,
                utilityPresentation: utilityPresentation,
                utilitySearchText: $utilitySearchText,
                utilityFilter: $utilityFilter,
                utilityActions: utilityActions,
                actions: BrowserSidebarInteractionActions(
                    selectSpace: selectSpace,
                    settleSpaceSelection: settleSpaceSelection,
                    presentExtensions: presentExtensions(for:),
                    presentSpaceSettings: presentSpaceSettings(for:),
                    createSpace: createSpace,
                    dismissUtilityOnBlankSpace: dismissUtilityOnBlankSpace,
                    confirmClearHistory: confirmClearHistory(for:),
                    handleAuxiliaryMouseAction: handleAuxiliaryMouseAction
                )
            )
            .confirmationDialog(
                clearHistoryConfirmation.map {
                    "Clear history for \($0.spaceName)?"
                } ?? "Clear history?",
                isPresented: clearHistoryConfirmationIsPresented,
                titleVisibility: .visible,
                presenting: clearHistoryConfirmation
            ) { confirmation in
                Button("Clear History", role: .destructive) {
                    clearHistoryConfirmation = nil
                    BrowserSidebarSpacePresentationPolicy.clearHistory(
                        confirmation,
                        in: browser,
                        accessController: spaceAccess
                    )
                }
            } message: { _ in
                Text("History in other Spaces is not affected.")
            }
            .onChange(of: utilityPresentation.surface) { previous, current in
                if previous != current {
                    utilitySearchText = ""
                    utilityFilter = .all
                }
                acknowledgeDownloads(ifPresented: current)
            }
            .onChange(of: selectedDownloads.map(\.id)) {
                acknowledgeDownloads(ifPresented: utilityPresentation.surface)
            }
            .onChange(of: clearHistoryConfirmationIsLive) { _, isLive in
                guard !isLive else { return }
                clearHistoryConfirmation = nil
            }
        }
    }

    private var clearHistoryConfirmationIsPresented: Binding<Bool> {
        Binding {
            clearHistoryConfirmationIsLive
        } set: { isPresented in
            if !isPresented {
                clearHistoryConfirmation = nil
            }
        }
    }

    private var clearHistoryConfirmationIsLive: Bool {
        guard let confirmation = clearHistoryConfirmation else { return false }
        return BrowserSidebarSpacePresentationPolicy.isLive(
            confirmation,
            in: browser,
            accessController: spaceAccess
        )
    }

    private var selectedDownloads: [BrowserDownloadItem] {
        utilityCoordinator.selectedDownloads
    }

    private var utilityActions: BrowserUtilityListActions {
        utilityCoordinator.actions
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    private func dismissUtilityOnBlankSpace() {
        utilityPresentation.handleInteraction(.sidebarBlankSpace)
    }

    private func acknowledgeDownloads(ifPresented surface: BrowserUtilitySurface?) {
        utilityCoordinator.acknowledgeDownloads(ifPresented: surface)
    }

    private func selectSpace(_ id: SpaceID) {
        guard id != browser.session.selectedSpaceID else { return }
        browser.selectSpace(id)
        guard let space = browser.selectedSpace,
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: space),
                in: browser,
                accessController: spaceAccess
            ) != nil
        else {
            pendingPageSelection = nil
            pages.deactivatePagePresentation()
            return
        }
        if BrowserSpaceContentSelectionPolicy.defersWebContentUntilPagerSettles {
            pendingPageSelection = BrowserSpaceRuntimeAssignment(space: space)
        } else {
            pages.select(session: browser.session)
        }
    }

    private func settleSpaceSelection(_ id: SpaceID) {
        guard let assignment = pendingPageSelection else { return }
        guard
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: id,
                in: browser,
                accessController: spaceAccess
            )
        else {
            if id == assignment.spaceID
                || browser.session.selectedSpaceID != assignment.spaceID
            {
                pendingPageSelection = nil
                pages.deactivatePagePresentation()
            }
            return
        }
        pendingPageSelection = nil
        pages.select(session: browser.session)
    }

    private func presentExtensions(for space: BrowserSpace) {
        spaceSettingsPresentation.present(
            .extensions,
            assignment: BrowserSpaceRuntimeAssignment(space: space)
        )
        openWindow(id: BrowserSceneID.settings.rawValue)
    }

    private func confirmClearHistory(for space: BrowserSpace) {
        clearHistoryConfirmation =
            BrowserSidebarSpacePresentationPolicy.clearHistoryConfirmation(
                for: space,
                in: browser,
                accessController: spaceAccess
            )
    }

    private func presentSpaceSettings(for space: BrowserSpace) {
        spaceSettingsPresentation.present(
            assignment: BrowserSpaceRuntimeAssignment(space: space)
        )
        openWindow(id: BrowserSceneID.settings.rawValue)
    }

    private func createSpace() {
        browser.addSpace()
        guard let space = browser.selectedSpace else { return }
        pages.select(session: browser.session)
        presentSpaceSettings(for: space)
    }

    private func handleAuxiliaryMouseAction(
        _ action: BrowserSidebarMouseButtonAction
    ) {
        let direction: BrowserChromeAccessibilityDirection
        switch action {
        case .previousSpace:
            direction = .previous
        case .nextSpace:
            direction = .next
        }

        guard
            let spaceID = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: browser),
                selectedSpaceID: browser.session.selectedSpaceID,
                direction: direction
            )
        else { return }
        selectSpace(spaceID)
    }
}

#Preview("Browser Sidebar — Tabs") {
    @Previewable @State var address = "https://developer.apple.com"
    @Previewable @State var isAddressEditing = false
    @Previewable @Namespace var commandSurfaceNamespace
    @Previewable @Namespace var tabPromotionNamespace
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let pages = BrowserSidebarPreviewFixture.makePages()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    BrowserSidebar(
        browser: browser,
        pages: pages,
        spaceAccess: spaceAccess,
        address: $address,
        isAddressEditing: $isAddressEditing,
        addressFocusRequest: 0,
        activateAddress: { isAddressEditing = true },
        submitAddress: {},
        openNewTab: {},
        sidebarToggleAction: .hide,
        toggleSidebar: {},
        commandSurfaceNamespace: commandSurfaceNamespace,
        tabPromotionNamespace: tabPromotionNamespace,
        utilityPresentation:
            BrowserSidebarPreviewFixture.makeUtilityPresentation(),
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState()
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 680)
}
