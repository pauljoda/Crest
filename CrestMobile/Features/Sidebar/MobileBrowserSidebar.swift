import SwiftUI

struct MobileBrowserSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let spaceAccess: BrowserSpaceAccessController
    let mode: MobileBrowserSidebarMode
    let compactChromeNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let activateAddress: () -> Void
    let selectTab: (TabID) -> Void
    let submitAddress: () -> Void
    let openURL: (URL) -> Void
    let openNewTab: () -> Void
    let showsCompactAddressBar: Bool
    let showsBottomSpaceSwitcher: Bool
    let compactPageIsFullyPresented: Bool
    let compactTransitionEnded: (CGSize) -> Void
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void
    let toggleSidebar: () -> Void
    let showsSidebarToggle: Bool
    let sidebarIsDocked: Bool
    let utilityPresentation: BrowserUtilityPresentationState

    @State private var showsPasswords = false
    @State private var showsSettings = false
    @State private var presentedSpaceSheet: MobileBrowserSidebarSpaceSheet?
    @State private var pendingPageSelection: BrowserSpaceRuntimeAssignment?
    @State private var utilitySearchText = ""
    @State private var utilityFilter = BrowserUtilityListFilter.all
    @State private var clearHistoryConfirmation: BrowserSidebarClearHistoryConfirmation?

    var body: some View {
        MobileBrowserSidebarPresentation(
            configuration: presentationConfiguration
        ) {
            MobileBrowserSidebarContent(configuration: contentConfiguration)
        }
    }

    private var selectedSidebarColorScheme: ColorScheme {
        guard MobileBrowserSidebarAppearancePolicy.usesSpaceForeground(for: mode),
            let space = browser.selectedSpace
        else { return colorScheme }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }

    private var contentConfiguration: MobileBrowserSidebarContentConfiguration {
        MobileBrowserSidebarContentConfiguration(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            mode: mode,
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            utilityPresentation: utilityPresentation,
            utilityActions: utilityActions,
            spaceActionsConfiguration: spaceActionsConfiguration,
            activateAddress: activateAddress,
            selectTab: selectTab,
            submitAddress: submitAddress,
            openNewTab: openNewTab,
            showsCompactAddressBar: showsCompactAddressBar,
            showsBottomSpaceSwitcher: showsBottomSpaceSwitcher,
            compactPageIsFullyPresented: compactPageIsFullyPresented,
            compactTransitionEnded: compactTransitionEnded,
            closePrivateBrowsing: closePrivateBrowsing,
            toggleSidebar: toggleSidebar,
            showsSidebarToggle: showsSidebarToggle,
            sidebarIsDocked: sidebarIsDocked,
            selectSpace: selectSpace,
            settleSpaceSelection: settlePendingPageSelection,
            showHistory: presentHistory,
            showPasswords: { showsPasswords = true },
            showSettings: { showsSettings = true },
            confirmClearHistory: confirmClearHistory
        )
    }

    private var presentationConfiguration: MobileBrowserSidebarPresentationConfiguration {
        MobileBrowserSidebarPresentationConfiguration(
            browser: browser,
            pages: pages,
            dataDeleter: dataDeleter,
            spaceAccess: spaceAccess,
            selectedColorScheme: selectedSidebarColorScheme,
            showsPasswords: $showsPasswords,
            showsSettings: $showsSettings,
            presentedSpaceSheet: $presentedSpaceSheet,
            clearHistoryConfirmation: $clearHistoryConfirmation,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            utilityPresentation: utilityPresentation,
            selectedDownloadIDs: selectedDownloads.map(\.id),
            selectedSpaceAssignment: selectedSpaceAssignment,
            clearHistoryConfirmationIsLive: clearHistoryConfirmationIsLive,
            selectTab: selectTab,
            openURL: openURL,
            acknowledgeDownloads: acknowledgeDownloads(ifPresented:)
        )
    }

    private var spaceActionsConfiguration: MobileSpaceActionsConfiguration {
        MobileSpaceActionsConfiguration(
            showSettings: { showsSettings = true },
            showArchive: { presentCompactSpaceSheet(.archive) },
            showDownloads: { presentCompactSpaceSheet(.downloads) },
            commonListsAreExpanded: utilitySwitcherIsExpanded,
            toggleCommonLists: toggleUtilitySwitcher,
            recordCommonListsTriggerFrame:
                utilityPresentation.recordTriggerFrame,
            togglePrivateBrowsing: togglePrivateBrowsing
        )
    }

    private var utilitySwitcherIsExpanded: Bool {
        utilityPresentation.isSwitcherExpanded
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
            spaceAccess: spaceAccess,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private func presentHistory() {
        if mode == .regularSidebar {
            selectUtility(.history)
        } else {
            presentCompactSpaceSheet(.history)
        }
    }

    private func presentCompactSpaceSheet(_ surface: BrowserUtilitySurface) {
        guard mode == .compactTabViewer,
            let assignment = selectedSpaceAssignment,
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ) != nil
        else { return }
        presentedSpaceSheet = MobileBrowserSidebarSpaceSheet(
            surface: surface,
            assignment: assignment
        )
        if surface == .downloads {
            pages.downloadCenter.acknowledgeItems(for: assignment.profileID)
        }
    }

    private func confirmClearHistory() {
        guard let space = browser.selectedSpace else { return }
        clearHistoryConfirmation =
            BrowserSidebarSpacePresentationPolicy.clearHistoryConfirmation(
                for: space,
                in: browser,
                accessController: spaceAccess
            )
    }

    private func toggleUtilitySwitcher() {
        guard mode == .regularSidebar else { return }
        utilityPresentation.toggleSwitcher(
            hasNewDownloads: !selectedNewDownloads.isEmpty
        )
    }

    private var selectedNewDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }

    private func selectUtility(_ surface: BrowserUtilitySurface) {
        guard mode == .regularSidebar else {
            utilityPresentation.present(surface)
            return
        }
        utilityPresentation.present(surface)
    }

    private func acknowledgeDownloads(ifPresented surface: BrowserUtilitySurface?) {
        utilityCoordinator.acknowledgeDownloads(ifPresented: surface)
    }

    private func selectSpace(_ spaceID: SpaceID) {
        guard spaceID != browser.session.selectedSpaceID else { return }
        if mode == .compactTabViewer {
            pages.deactivatePagePresentation()
        }
        browser.selectSpace(spaceID)
        guard let space = browser.selectedSpace,
            !spaceAccess.isLocked(space)
        else {
            pendingPageSelection = nil
            pages.deactivatePagePresentation()
            address = ""
            isAddressEditing = false
            return
        }
        if mode == .regularSidebar {
            address = browser.selectedTab?.url?.absoluteString ?? ""
            let defersWebContentSelection = BrowserSpaceContentSelectionPolicy
                .defersWebContentUntilPagerSettles
            if reduceMotion || !defersWebContentSelection {
                pages.select(session: browser.session)
            } else {
                pendingPageSelection = BrowserSpaceRuntimeAssignment(space: space)
            }
        } else {
            pendingPageSelection = nil
        }
        isAddressEditing = false
    }

    private func settlePendingPageSelection(_ settledSpaceID: SpaceID) {
        guard let assignment = pendingPageSelection else { return }
        guard
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: settledSpaceID,
                in: browser,
                accessController: spaceAccess
            )
        else {
            if settledSpaceID == assignment.spaceID
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

    private var selectedSpaceAssignment: BrowserSpaceRuntimeAssignment? {
        browser.selectedSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }
}

#Preview("Mobile Browser Sidebar") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileBrowserSidebar(
        browser: fixture.browser,
        pages: fixture.pages,
        dataDeleter: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        mode: .regularSidebar,
        compactChromeNamespace: compactChromeNamespace,
        tabPromotionNamespace: tabPromotionNamespace,
        address: $address,
        isAddressEditing: $isAddressEditing,
        activateAddress: {},
        selectTab: { _ in },
        submitAddress: {},
        openURL: { _ in },
        openNewTab: {},
        showsCompactAddressBar: true,
        showsBottomSpaceSwitcher: true,
        compactPageIsFullyPresented: true,
        compactTransitionEnded: { _ in },
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {},
        toggleSidebar: {},
        showsSidebarToggle: true,
        sidebarIsDocked: true,
        utilityPresentation: BrowserUtilityPresentationState()
    )
}
