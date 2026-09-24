import Foundation

extension BrowserStore {
    /// Borrows a Space's profile and policies while keeping browsing records
    /// in a separate, memory-only family. The window starts without a tab.
    func makeTemporaryWindowStore(
        in assignment: BrowserSpaceRuntimeAssignment, id: BrowserWindowID = BrowserWindowID()
    ) -> BrowserStore? {
        guard space(matching: assignment) != nil else { return nil }
        let settingsBrowser = profileSettingsBrowser.makeWindowStore(
            BrowserWindowOpening(showingSpaceID: assignment.spaceID, restoresTabs: false))
        let workspaceFamily: BrowserStoreFamily
        do { workspaceFamily = try settingsBrowser.family.makeBorrowed(in: assignment, settingsBrowser: settingsBrowser) }
        catch { localSyncErrorDescription = "Core workspace creation failed: \(error)"; return nil }
        return BrowserStore(
            opening: BrowserWindowOpening(id: id),
            credentialVault: credentialVault,
            syncCoordinator: nil,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: workspaceFamily,
            linkPreferences: linkPreferences,
            core: core
        )
    }

    /// Settings in a temporary window edit the canonical profile through their
    /// own selection facade. Its native tab still belongs to the workspace.
    var profileSettingsBrowser: BrowserStore { family.temporarySettingsBrowser ?? self }

    /// The store that applies a Space command issued from this window. The
    /// core's routing rule sends a borrowed workspace's profile settings to the
    /// Space it borrows from and refuses Space organization there; nil when
    /// nobody may apply the command, including when the core cannot answer.
    func spaceCommandOwner(_ command: BrowserSessionOperation, in spaceID: SpaceID? = nil) -> BrowserStore? {
        switch BrowserCorePolicy.workspaceCommandRoute(command, borrowed: isTemporaryWorkspace) {
        case .local: return self
        case .source:
            guard let assignment = temporarySourceAssignment, assignment.spaceID == spaceID,
                let source = family.temporarySettingsBrowser, source.space(matching: assignment) != nil
            else { return nil }
            return source
        case .rejected, nil: return nil
        }
    }

    /// Refreshes borrowed identity and policy without importing any source tabs,
    /// folders, history, or archive. The scene closes when the source is gone.
    @discardableResult
    func reconcileTemporarySource() -> Bool {
        guard family.refreshBorrowed() else { return false }
        stageSync()
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
        guard sourceAssignment == destinationAssignment, let source = space(matching: sourceAssignment),
            source.contains(id), destination.space(matching: destinationAssignment) != nil,
            isPrivateBrowsing == destination.isPrivateBrowsing else { return false }
        if family === destination.family { return true }
        return (try? BrowserStoreFamily.prepareTransfer(id, assignment: sourceAssignment,
            source: self, destination: destination, selecting: false)) != nil
    }

    @discardableResult
    func transferTab(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment,
        selecting: Bool = true
    ) -> Bool {
        guard sourceAssignment == destinationAssignment, let source = space(matching: sourceAssignment),
            source.contains(id), destination.space(matching: destinationAssignment) != nil,
            isPrivateBrowsing == destination.isPrivateBrowsing else { return false }
        if family === destination.family {
            if selecting {
                guard destination.activateSessionTab(id, in: destinationAssignment.spaceID) else { return false }
                destination.stageSync(urgency: .coalesced)
            }
            return true
        }
        do {
            let command = try BrowserStoreFamily.prepareTransfer(id, assignment: sourceAssignment,
                source: self, destination: destination, selecting: selecting)
            try BrowserStoreFamily.transfer(command, source: self, destination: destination)
            tabMultiSelection.clear()
            return true
        } catch {
            localSyncErrorDescription = "Core workspace transfer failed: \(error)"
            return false
        }
    }
}
