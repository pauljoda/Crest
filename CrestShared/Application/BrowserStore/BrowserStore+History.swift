import Foundation

// MARK: - History and Cleanup

extension BrowserStore {
    /// Keeps a Quick Window's page, `pageID`, in the archive of the Space it
    /// lived in, and answers whether the core kept it. The page may already
    /// be gone, as one memory pressure took back is; the core names a page it
    /// is given no title for.
    @discardableResult
    func archiveTransientPage(
        _ pageID: UUID, url: URL, title: String?, matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.perform(
            ArchiveTransientPage(
                workspaceID: family.workspaceID, pageID: pageID, spaceID: assignment.spaceID.rawValue,
                address: url.absoluteString, title: title),
            from: self) != nil
    }

    func clearHistory() {
        guard selectedSpace != nil else { return }
        clearHistory(in: selectedSpaceID)
    }

    func clearHistory(in spaceID: SpaceID) {
        sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: spaceID.rawValue))
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: assignment.spaceID.rawValue))
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
        sendRecords(CleanUpCurrentTabs(workspaceID: family.workspaceID, spaceID: spaceID.rawValue))
    }

    func restoreArchivedTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        sendRecords(
            RestoreArchivedTab(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: selectedSpaceID.rawValue,
                tabID: id.rawValue))
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
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: assignment.spaceID.rawValue,
                tabID: id.rawValue))
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
                workspaceID: family.workspaceID, spaceID: assignment.spaceID.rawValue, address: url.absoluteString))
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
                workspaceID: family.workspaceID, spaceID: assignment.spaceID.rawValue, start: startDate, end: endDate))
    }
}

// MARK: - Data Retention

extension BrowserStore {
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
        // Retention is one field of the same Space preferences record every
        // other settings surface writes, so it takes the same core command, and
        // the core's own sweep then applies it: a changed retention is never
        // held back by the last sweep.
        guard setCoreSpaceValue(.spaceBrowsingPreferences, preferences, in: spaceID) else { return }
        sweepExpiredBrowsingData()
    }
}
