import Foundation

// MARK: - History and Cleanup

extension BrowserStore {
    func recordVisit(url: URL, title: String?) {
        guard selectedSpace != nil else { return }
        let spaceID = selectedSpaceID
        guard recordSessionVisit(url: url, title: title, in: spaceID) else { return }
    }

    func recordVisit(url: URL, title: String?, in spaceID: SpaceID) {
        guard recordSessionVisit(url: url, title: title, in: spaceID) else { return }
    }

    @discardableResult
    func recordVisit(
        url: URL,
        title: String?,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard recordSessionVisit(url: url, title: title, in: assignment.spaceID) else { return false }
        return true
    }

    private func recordSessionVisit(url: URL, title: String?, in spaceID: SpaceID) -> Bool {
        family.executeRecords(
            .historyVisit, in: spaceID,
            arguments: BrowserSessionArguments.HistoryVisit(url: url.absoluteString, title: title), from: self)
    }

    func archiveTransientPage(url: URL, title: String?, in spaceID: SpaceID) {
        guard let space = session.space(id: spaceID) else { return }
        _ = archiveTransientPage(url: url, title: title, matching: BrowserSpaceRuntimeAssignment(space: space))
    }

    @discardableResult
    func archiveTransientPage(
        url: URL,
        title: String?,
        matching assignment: BrowserSpaceRuntimeAssignment,
        requestID: UUID = UUID()
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        let date = Date.now
        let tab = BrowserTab(title: title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? url.absoluteString,
            url: url, placement: .current, lastActivatedAt: date)
        guard
            family.execute(
                .transientArchive, in: assignment.spaceID,
                arguments: BrowserSessionArguments.TransientArchive(requestId: requestID, tab: tab),
                from: self, at: date) != nil
        else { return false }
        return true
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
