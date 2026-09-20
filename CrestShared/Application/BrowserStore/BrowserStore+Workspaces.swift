import Foundation

extension BrowserStore {
    private struct TabTransferPreparation {
        let sourceSpace: BrowserSpace
        let targetSpace: BrowserSpace
        let tab: BrowserTab
        let placement: BrowserTabPlacementPlan?
    }

    /// Borrows a Space's profile and policies while keeping browsing records
    /// in a separate, memory-only family. The window starts without a tab.
    func makeTemporaryWindowStore(in assignment: BrowserSpaceRuntimeAssignment) -> BrowserStore? {
        guard var space = space(matching: assignment) else { return nil }
        space.folders = []
        space.tabs = []
        space.splitGroups = []
        space.archivedTabs = []
        space.history = []
        space.selectedTabID = nil
        let workspace = BrowserSession(
            spaces: [space], selectedSpaceID: space.id, defaultSpaceID: space.id
        )
        let settingsBrowser = profileSettingsBrowser.makeWindowStore(
            restoresTabSelection: false, selectingSpaceID: assignment.spaceID)
        return BrowserStore(
            session: workspace,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: credentialVault,
            syncCoordinator: nil,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(
                session: workspace, browsingMode: browsingMode,
                temporarySourceAssignment: assignment, temporarySettingsBrowser: settingsBrowser),
            linkPreferences: linkPreferences
        )
    }

    /// Settings in a temporary window edit the canonical profile through their
    /// own selection facade. Its native tab still belongs to the workspace.
    var profileSettingsBrowser: BrowserStore { family.temporarySettingsBrowser ?? self }

    func temporaryProfileSettingsAuthority(in spaceID: SpaceID) -> BrowserStore? {
        guard let assignment = temporarySourceAssignment, assignment.spaceID == spaceID,
            let source = family.temporarySettingsBrowser, source.space(matching: assignment) != nil
        else { return nil }
        return source
    }

    /// Refreshes borrowed identity and policy without importing any source tabs,
    /// folders, history, or archive. The scene closes when the source is gone.
    @discardableResult
    func reconcileTemporarySource(from source: BrowserSession) -> Bool {
        guard let assignment = temporarySourceAssignment,
            let sourceSpace = source.space(id: assignment.spaceID), assignment.matches(sourceSpace),
            let local = family.authoritativeSession.space(id: assignment.spaceID)
        else { return false }
        let borrowed = BrowserTemporaryWorkspacePolicy.borrowing(sourceSpace, keeping: local)
        guard borrowed != local else { return true }
        var updated = family.authoritativeSession
        guard let index = updated.spaces.firstIndex(where: { $0.id == assignment.spaceID }) else { return false }
        updated.spaces[index] = borrowed
        session = updated
        persist(scope: .core)
        return true
    }

    /// Transfers data ownership without invoking close/delete or archiving the
    /// tab. The scene coordinator moves its matching live runtime separately.
    func canTransferTab(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        prepareTabTransfer(id, matching: sourceAssignment, to: destination, in: destinationAssignment) != nil
    }

    @discardableResult
    func transferTab(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment,
        selecting: Bool = true
    ) -> Bool {
        guard
            let prepared = prepareTabTransfer(
                id, matching: sourceAssignment, to: destination, in: destinationAssignment
            )
        else { return false }
        if family === destination.family {
            if selecting {
                destination.session.activateTab(id, in: destinationAssignment.spaceID)
                destination.persist(syncUrgency: .coalesced, scope: .core)
            }
            return true
        }
        guard let plan = prepared.placement else { return false }
        let sourceSpace = prepared.sourceSpace
        let targetSpace = prepared.targetSpace
        let tab = prepared.tab

        var sourceSession = session
        var destinationSession = destination.session
        guard let sourceIndex = sourceSession.spaces.firstIndex(where: { $0.id == sourceSpace.id }),
            let tabIndex = sourceSession.spaces[sourceIndex].tabs.firstIndex(where: { $0.id == id }),
            let targetIndex = destinationSession.spaces.firstIndex(where: { $0.id == targetSpace.id })
        else { return false }
        var history = tabSelectionHistory
        let fallback = history.fallbackTabID(
            afterDismissing: id, in: sourceSpace.id,
            availableTabIDs: Set(sourceSpace.tabs.map(\.id)).subtracting([id])
        )
        sourceSession.preserveFolderOrder(in: sourceIndex, removing: [id])
        sourceSession.spaces[sourceIndex].tabs.remove(at: tabIndex)
        if sourceSpace.selectedTabID == id {
            sourceSession.spaces[sourceIndex].selectedTabID = fallback
        }
        sourceSession.normalizeSplitGroupsAfterUserMutation(in: sourceSpace.id)

        var moved = plan.placing(tab)
        moved.splitGroupID = nil
        moved.markPositionModified(at: .now)
        destinationSession.spaces[targetIndex].tabs.insert(moved, at: plan.insertionIndex)
        if selecting {
            destinationSession.activateTab(id, in: targetSpace.id)
        }
        guard BrowserStoreFamily.replaceSessions(
            source: self, sourceSession: sourceSession,
            destination: destination, destinationSession: destinationSession
        ) else { return false }
        tabSelectionHistory = history
        tabSelectionHistory.reconcile(session: session)
        tabMultiSelection.clear()
        persist(syncUrgency: .coalesced, scope: .core)
        destination.persist(syncUrgency: .coalesced, scope: .favicon(for: id))
        return true
    }

    private func prepareTabTransfer(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> TabTransferPreparation? {
        guard sourceAssignment == destinationAssignment,
            let sourceSpace = space(matching: sourceAssignment),
            let tab = sourceSpace.tabs.first(where: { $0.id == id }),
            let targetSpace = destination.space(matching: destinationAssignment)
        else { return nil }
        if family === destination.family {
            return TabTransferPreparation(sourceSpace: sourceSpace, targetSpace: targetSpace, tab: tab, placement: nil)
        }
        guard !destination.session.tabIDs.contains(id),
            !destination.session.spaces.contains(where: { $0.archivedTabs.contains { $0.id == id } }),
            let placement = BrowserTabPlacementPlan(
                moving: tab, to: .current,
                requestedIndex: BrowserTabInsertionPolicy.requestedIndex(
                    after: targetSpace.selectedTabID, in: targetSpace),
                in: targetSpace, among: targetSpace.tabs
            )
        else { return nil }
        return TabTransferPreparation(
            sourceSpace: sourceSpace, targetSpace: targetSpace, tab: tab, placement: placement)
    }
}
