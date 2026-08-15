extension BrowserRootModel {
    func prepareBrowser() async {
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: chrome.columnVisibility != .detailOnly
        )
        guard !hasRestoredExtensions else { return }
        await pages.restoreExtensions(in: browser.session)
        await pages.prepareContentBlocking()
        hasRestoredExtensions = true
        address = browser.selectedTab?.url?.absoluteString ?? ""
        if startupBehavior.activatesRestoredTab {
            synchronizeSelection()
        }
    }

    func reconcileExtensions() {
        pages.reconcile(session: browser.session)
    }

    /// Republishes tab state that lives on the page rather than in the session,
    /// so `tabs.onUpdated` reports load progress and reader mode. Deliberately
    /// narrower than `reconcileExtensions()`, which also re-evaluates page
    /// residency and is far too heavy for a load beginning or ending.
    func reconcileExtensionTabActivity() {
        pages.extensionControllerPool.reconcileExtensionState(
            in: browser.session
        )
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons(in: browser.session)
    }

    func reconcileContentBlocking() {
        guard hasRestoredExtensions else { return }
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess(in: browser.session)
    }

    func reloadContentBlocking() {
        guard hasRestoredExtensions else { return }
        let session = browser.session
        Task { await pages.reloadContentBlocking(in: session) }
    }

    func relockProtectedSpaces(_ spaceIDs: Set<SpaceID>) {
        // The Space itself, not just its ID: relocking has to reach the
        // profile its archived tab state is filed under, and that state
        // outlives the resident pages an ID alone can find.
        for space in browser.session.spaces where spaceIDs.contains(space.id) {
            pages.relockProtectedSpace(space)
        }
    }
}
