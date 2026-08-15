extension MobileBrowserRootModel {
    var selectionSnapshot: MobileBrowserRootSelectionSnapshot {
        MobileBrowserRootSelectionSnapshot(
            sessionRevision: browser.sessionRevision,
            selectedSpaceID: browser.session.selectedSpaceID,
            selectedProfileID: browser.selectedSpace?.profile.id,
            assignment: browser.selectedSpace.flatMap { space in
                browser.selectedTab.map { tab in
                    BrowserTabRuntimeAssignment(
                        tabID: tab.id,
                        spaceID: space.id,
                        profileID: space.profile.id
                    )
                }
            }
        )
    }

    func lockSnapshot(
        presentation: MobileBrowserPresentation
    ) -> MobileBrowserRootLockSnapshot {
        MobileBrowserRootLockSnapshot(
            sessionRevision: browser.sessionRevision,
            selectedSpaceID: browser.session.selectedSpaceID,
            selectedProfileID: browser.selectedSpace?.profile.id,
            isLocked: selectedSpaceIsLocked,
            presentation: presentation
        )
    }

    var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(browser: browser, pages: pages)
    }

    var selectedPage: MobileBrowserPage? {
        selectedPageActions?.activePage
    }

    var renderedPageSelection: BrowserTabRuntimeAssignment? {
        guard let page = selectedPage else { return nil }
        return BrowserTabRuntimeAssignment(
            tabID: page.tabID,
            spaceID: page.spaceID,
            profileID: page.profileID
        )
    }

    var selectedSpaceIsLocked: Bool {
        guard let space = browser.selectedSpace else { return false }
        return spaceAccess.isLocked(space)
    }

    var lockedSpaceIDs: Set<SpaceID> {
        Set(
            browser.session.spaces.compactMap { space in
                spaceAccess.isLocked(space) ? space.id : nil
            }
        )
    }

    @discardableResult
    func synchronizeSelection(
        from previous: MobileBrowserRootSelectionSnapshot,
        to current: MobileBrowserRootSelectionSnapshot
    ) -> Bool {
        let change = MobileBrowserRootSelectionChange.resolve(
            from: previous,
            to: current
        )
        guard change != .unchanged, hasPreparedBrowser else { return false }
        guard !navigation.defersPageActivation else { return true }
        synchronizeSelection()
        return true
    }

    func synchronizeLockTransition(
        from previous: MobileBrowserRootLockSnapshot,
        to current: MobileBrowserRootLockSnapshot
    ) {
        if current.isLocked {
            navigation.prepareForSpaceSwitch()
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        guard previous.isLocked, hasPreparedBrowser else { return }
        switch MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
            in: current.presentation
        ) {
        case .tabViewer:
            navigation.prepareForSpaceSwitch()
            pages.deactivatePagePresentation()
            address = browser.selectedTab?.url?.absoluteString ?? ""
        case .selectedPage:
            activateSelectedTab()
        }
    }

    func synchronizeSelection() {
        guard !selectedSpaceIsLocked else {
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }
}
