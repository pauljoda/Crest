import SwiftUI

extension MobileBrowserRootModel {
    var commandController: MobileBrowserCommandController {
        MobileBrowserCommandController(browser: browser, pages: pages)
    }

    func commandContext(
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        layoutDirection: LayoutDirection,
        togglePrivateBrowsing: @escaping () -> Void,
        openNewTab: @escaping () -> Void,
        openLocation: @escaping () -> Void,
        prepareForSelectionSynchronization: @escaping () -> Void,
        toggleSidebar: @escaping () -> Void,
        presentHistory: @escaping () -> Void,
        presentArchive: @escaping () -> Void,
        presentDownloads: @escaping () -> Void
    ) -> MobileBrowserCommandContext {
        let controller = commandController
        let pageActions = selectedPageActions
        let contentBlockingAction = pageActions.map {
            MobileContentBlockingAction(browser: browser, pages: $0)
        }
        return MobileBrowserCommandContext(
            isPrivateBrowsing: browser.isPrivateBrowsing,
            canGoBack: pageActions?.canGoBack == true,
            canGoForward: pageActions?.canGoForward == true,
            hasSelectedTab: browser.selectedTab != nil,
            hasActivePage: pageActions?.isAvailable == true,
            isLoading: pageActions?.activePage?.isLoading == true,
            canDismissSelectedTab: controller.canDismissSelectedTab
                && transientBrowsing.peekRequest == nil
                && transientBrowsing.quickWindowRequest == nil,
            canArchiveSelectedTab: controller.canArchiveSelectedTab
                && transientBrowsing.peekRequest == nil
                && transientBrowsing.quickWindowRequest == nil,
            canDuplicateSelectedTab: controller.canDuplicateSelectedTab,
            canReopenClosedTab: controller.canReopenClosedTab,
            tabCount: controller.orderedTabs.count,
            spaceCount: browser.session.spaces.count,
            isSelectedTabInSplit: controller.isSelectedTabInSplit,
            canSplitWithNextTab: controller.canSplitWithNextTab,
            layoutDirection: layoutDirection,
            readerModeActionTitle: pageActions?.readerModeActionTitle ?? "Show Reader",
            canToggleReaderMode: pageActions?.readerModeState.canToggle == true,
            contentBlockingActionTitle: MobileContentBlockingActionTitle.resolve(
                policy: browser.selectedSpace?.browsingPreferences
                    .contentBlockingPolicy
            ),
            openNewTab: openNewTab,
            togglePrivateBrowsing: togglePrivateBrowsing,
            openLocation: openLocation,
            goBack: { pageActions?.goBack() },
            goForward: { pageActions?.goForward() },
            reloadOrStop: { pageActions?.reloadOrStop() },
            stopLoading: { pageActions?.stopLoading() },
            reloadFromOrigin: { pageActions?.reloadFromOrigin() },
            toggleSelectedTabPinned: {
                _ = self.toggleSelectedTabPinnedFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            duplicateSelectedTab: {
                _ = self.duplicateSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            reopenClosedTab: {
                _ = self.reopenClosedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            cleanupCurrentTabs: {
                self.cleanupCurrentTabsFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            dismissSelectedTab: {
                _ = self.dismissSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            archiveSelectedTab: {
                _ = self.archiveSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectPreviousTab: {
                _ = self.selectPreviousTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectNextTab: {
                _ = self.selectNextTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectMostRecentTab: {
                _ = self.selectMostRecentTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectTab: { index in
                _ = self.selectTabFromCommand(
                    index,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            splitWithNextTab: {
                _ = self.splitWithNextTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            focusNextSplitCard: {
                _ = self.focusAdjacentSplitCardFromCommand(
                    offset: 1,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            focusPreviousSplitCard: {
                _ = self.focusAdjacentSplitCardFromCommand(
                    offset: -1,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            removeTabFromSplit: {
                _ = self.removeSelectedTabFromSplitFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            separateSplitTabs: {
                _ = self.separateSplitTabsFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            canMoveFocusedSplitCard: { offset in
                self.commandController.canMoveFocusedSplitCard(offset: offset)
            },
            moveFocusedSplitCard: { offset in
                _ = self.moveFocusedSplitCardFromCommand(offset: offset)
            },
            selectPreviousSpace: {
                _ = self.selectPreviousSpaceFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectNextSpace: {
                _ = self.selectNextSpaceFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectSpace: { index in
                _ = self.selectSpaceFromCommand(
                    index,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            toggleReaderMode: { pageActions?.toggleReaderMode() },
            toggleContentBlocking: {
                guard let contentBlockingAction else { return }
                _ = await contentBlockingAction.perform()
            },
            presentFind: { pageActions?.presentFind() },
            zoomIn: { pageActions?.zoomIn() },
            zoomOut: { pageActions?.zoomOut() },
            resetZoom: { pageActions?.resetZoom() },
            copyPageLink: { _ = pageActions?.copyPageLink() },
            copyPageLinkAsMarkdown: {
                _ = pageActions?.copyPageLinkAsMarkdown()
            },
            printPage: { pageActions?.printPage() },
            toggleSidebar: toggleSidebar,
            presentHistory: presentHistory,
            presentArchive: presentArchive,
            presentDownloads: presentDownloads
        )
    }

    @discardableResult
    func toggleSelectedTabPinnedFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.toggleSelectedTabPinned() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func duplicateSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.duplicateSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func reopenClosedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.reopenClosedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    func cleanupCurrentTabsFromCommand(
        beforeSynchronization: () -> Void = {}
    ) {
        commandController.cleanupCurrentTabs()
        beforeSynchronization()
        synchronizeAfterCommandSelection()
    }

    @discardableResult
    func dismissSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.dismissSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func archiveSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.archiveSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectPreviousTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectPreviousTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectNextTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNextTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectMostRecentTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectMostRecentTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectTabFromCommand(
        _ index: Int,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectTab(at: index) != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectPreviousSpaceFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectPreviousSpace() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectNextSpaceFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNextSpace() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectSpaceFromCommand(
        _ index: Int,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectSpace(at: index) != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    /// Moves focus between the cards already on screen.
    ///
    /// Deliberately does not run `synchronizeAfterCommandSelection()`: focus
    /// inside a presented split changes which card chrome speaks for and nothing
    /// about what is presented, so re-entering the compact page presentation
    /// would animate a transition to the surface already showing.
    @discardableResult
    func focusAdjacentSplitCardFromCommand(
        offset: Int,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.focusAdjacentSplitCard(offset: offset) != nil
        else { return false }
        beforeSynchronization()
        address = browser.selectedTab?.url?.absoluteString ?? ""
        return true
    }

    /// Reorders the cards already on screen.
    ///
    /// Like the focus step, and for the same reason, this deliberately skips
    /// `synchronizeAfterCommandSelection()`: the selection does not move, so
    /// re-entering the compact page presentation would animate a transition to
    /// the surface already showing. The address bar keeps speaking for the same
    /// card, so it is not rewritten either.
    @discardableResult
    func moveFocusedSplitCardFromCommand(offset: Int) -> Bool {
        commandController.moveFocusedSplitCard(offset: offset) != nil
    }

    @discardableResult
    func splitWithNextTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.splitWithNextTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func removeSelectedTabFromSplitFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.removeSelectedTabFromSplit() != nil else {
            return false
        }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func separateSplitTabsFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.separateSplitTabs() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    private func synchronizeAfterCommandSelection() {
        address = browser.selectedTab?.url?.absoluteString ?? ""
        if browser.selectedTab == nil {
            navigation.showTabViewer()
        } else {
            navigation.selectTab()
        }
    }
}
