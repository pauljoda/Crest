extension BrowserStore {
    func resetPrivateBrowsingSession() {
        guard isPrivateBrowsing else { return }
        syncStageTask?.cancel()
        syncStageTask = nil
        syncStageGeneration = 0
        credentialSaveOperations.removeAll()
        family.resetDeletionState()
        tabDragState.end()
        folderDragState.end()
        session = .privateBrowsing()
        localSyncErrorDescription = nil
        family.publish(session, from: self)
        persistence.save(session)
    }

    func makeWindowStore(restoring savedState: BrowserWindowState? = nil) -> BrowserStore {
        var windowSession = family.authoritativeSession
        if var savedState {
            savedState.repair(using: windowSession)
            windowSession.selectedSpaceID = savedState.selectedSpaceID
            for index in windowSession.spaces.indices {
                let spaceID = windowSession.spaces[index].id
                guard let tabID = savedState.selectedTabIDsBySpace[spaceID],
                    windowSession.spaces[index].contains(tabID)
                else { continue }
                windowSession.spaces[index].selectedTabID = tabID
            }
        }
        windowSession.selectDefaultSpaceForLaunch()
        windowSession.repairRuntimeIntegrity()
        let store = BrowserStore(
            session: windowSession,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: family,
            cloudSyncChangeHandler: cloudSyncChangeHandler
        )
        store.localSyncErrorDescription = localSyncErrorDescription
        return store
    }
}
