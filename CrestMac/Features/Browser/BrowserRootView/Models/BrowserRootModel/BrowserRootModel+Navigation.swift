extension BrowserRootModel {
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

    func submitAddress() {
        guard
            let url = AddressResolver.resolve(
                address,
                searchProvider: browser.selectedSpace?.browsingPreferences.searchProvider
                    ?? .google
            )
        else { return }
        browser.navigateSelectedTab(to: url)
        pages.load(url)
        address = url.absoluteString
        isAddressEditing = false
        AddressFocusAction.resign()
    }

    func synchronizeAfterSelectionChange() {
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        guard BrowserSpaceContentSelectionPolicy.rootObserverDefersSpaceChanges else {
            synchronizeSelection()
            return
        }
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }

    func synchronizeAfterLockChange() {
        guard hasRestoredExtensions else { return }
        synchronizeSelection()
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

    func handleAuxiliaryMouseAction(
        _ action: BrowserSidebarMouseButtonAction
    ) {
        let direction: BrowserSpaceSwipeDirection
        switch action {
        case .previousSpace:
            direction = .previous
        case .nextSpace:
            direction = .next
        }
        guard browser.selectAdjacentSpace(direction) != nil else { return }
        pages.select(session: browser.session)
    }
}
