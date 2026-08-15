extension MobileBrowserRootModel {
    func presentationChanged(to presentation: MobileBrowserPresentation) {
        navigation.adapt(to: presentation)
        guard presentation == .regular else { return }
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: navigation.regularSidebarIsPresented
        )
    }

    func prepareBrowser() async {
        guard !hasPreparedBrowser else { return }
        await pages.prepareContentBlocking()
        hasPreparedBrowser = true
        guard startupBehavior.activatesRestoredTab,
            !navigation.defersPageActivation
        else { return }
        synchronizeSelection()
    }

    /// Brings resident pages back in line with the tabs the session still has,
    /// releasing pages whose tab moved to another Space or profile and dropping
    /// the archived state of tabs that are gone for good.
    func reconcileResidentPages() {
        pages.reconcile(session: browser.session)
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons(in: browser.session)
    }

    /// Carries each Space's "save passwords" preference into the running pages, so
    /// turning it off takes effect on the surface the user is looking at rather
    /// than only on the next page they open.
    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess(in: browser.session)
    }

    func reconcileContentBlocking() {
        guard hasPreparedBrowser else { return }
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func reloadContentBlocking() {
        guard hasPreparedBrowser else { return }
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

    func recordRenderedSelection(_ selection: BrowserTabRuntimeAssignment?) {
        guard let selection else { return }
        windowState?.recordRenderedTab(
            selection.tabID,
            in: selection.spaceID,
            session: browser.session
        )
    }

    func regularSidebarPresentationChanged(_ isPresented: Bool) {
        windowState?.captureSidebar(isPresented: isPresented)
        if !isPresented {
            navigation.utilityPresentation.dismiss()
        }
    }
}
