import Foundation

// MARK: - History and Cleanup

extension BrowserStore {
    /// Keeps a Quick Window's page, `pageID`, in the archive of the Space it
    /// lived in, at the address and title the core holds for it, and answers
    /// whether the core kept it. The page may already be gone, as one memory
    /// pressure took back is; the core keeps what it showed last.
    @discardableResult
    func archiveTransientPage(_ pageID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.perform(
            ArchiveTransientPage(workspaceID: family.workspaceID, pageID: pageID, spaceID: assignment.spaceID),
            from: self) != nil
    }

    func clearHistory() {
        guard selectedSpace != nil else { return }
        clearHistory(in: selectedSpaceID)
    }

    func clearHistory(in spaceID: SpaceID) {
        sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: spaceID))
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: assignment.spaceID))
    }

    func cleanupCurrentTabs() {
        sendRecords(CleanUpCurrentTabs(workspaceID: family.workspaceID, spaceID: nil))
    }

    /// Applies every Space's tab and stored-record retention policies to a
    /// session that is already running, rather than only at launch. Windows
    /// share one session, and the core sweeps it at most once a minute unless
    /// a Space's retention changed, so every window may ask whenever it
    /// becomes active. A sweep that expires nothing changes nothing.
    func sweepExpiredBrowsingData() {
        sendRecords(SweepExpiredRecords(workspaceID: family.workspaceID))
    }

    /// Sweeps once for the scene that just became active, then keeps sweeping on
    /// `BrowserCurrentTabCleanupSchedule.sweepInterval`.
    ///
    /// The caller owns the lifetime: a scene ties this to being active, so the
    /// loop is cancelled — and the sweep suspends — as soon as the scene stops
    /// being active. Every pass runs on the main actor, so windows serialize.
    func sweepExpiredBrowsingDataWhileSceneIsActive(
        additionalSweep: @MainActor () -> Void = {}
    ) async {
        sweepExpiredBrowsingData()
        additionalSweep()
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    for: .seconds(BrowserCurrentTabCleanupSchedule.sweepInterval)
                )
            } catch {
                return
            }
            sweepExpiredBrowsingData()
            additionalSweep()
        }
    }

    func cleanupCurrentTabs(in spaceID: SpaceID) {
        guard session.space(id: spaceID) != nil else { return }
        sendRecords(CleanUpCurrentTabs(workspaceID: family.workspaceID, spaceID: spaceID))
    }

    func restoreArchivedTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        sendRecords(
            RestoreArchivedTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: selectedSpaceID,
                tabID: id))
    }

    @discardableResult
    func restoreArchivedTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            selectedSpaceID == assignment.spaceID,
            space.archivedTabs.contains(where: { $0.id == id })
        else { return false }
        return sendRecords(
            RestoreArchivedTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: assignment.spaceID,
                tabID: id))
    }

    /// Runs a history, archive or retention intent from this window, and
    /// answers whether it changed the session.
    @discardableResult
    private func sendRecords(_ intent: some Intent) -> Bool {
        family.send(intent, from: self, failure: "Core record command failed")
    }
}

// MARK: - Deletion

/// Space-exact targeted history removal.
///
/// Every entry point takes a ``BrowserSpaceRuntimeAssignment`` rather than a
/// bare `SpaceID`, matching the rest of the deletion surface: a Space that was
/// replaced or is mid-deletion must not have its successor's history erased by
/// a request captured against the old one.
extension BrowserStore {
    @discardableResult
    func deleteHistory(
        for url: URL,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return sendRecords(
            RemoveHistoryAddress(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, address: url.absoluteString))
    }

    @discardableResult
    func deleteHistory(
        from startDate: Date,
        until endDate: Date,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return sendRecords(
            RemoveHistoryRange(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, start: startDate, end: endDate))
    }
}

// MARK: - Data Retention

extension BrowserStore {
    /// Sets how long a Space keeps what it browses. The core sweeps the Space
    /// under the new retention as it accepts it, so a changed retention is
    /// never held back by the last sweep.
    func updateDataRetentionPreferences(
        _ retention: BrowserSpaceDataRetentionPreferences,
        in spaceID: SpaceID
    ) {
        guard var preferences = session.space(id: spaceID)?.browsingPreferences,
            preferences.dataRetention != retention
        else {
            return
        }
        preferences.dataRetention = retention
        updateBrowsingPreferences(preferences, in: spaceID)
    }
}
