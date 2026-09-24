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
        guard family.executeRecords(.historyClear, in: spaceID, from: self) else { return }
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard family.executeRecords(.historyClear, in: assignment.spaceID, from: self) else { return false }
        return true
    }

    func cleanupCurrentTabs() {
        guard family.executeRecords(.recordsCleanup, from: self) else { return }
    }

    /// Applies every Space's tab and stored-record retention policies to a
    /// session that is already running, rather than only at launch.
    ///
    /// Returns whether this call performed the sweep: windows share a store
    /// family, so the first requester inside
    /// `BrowserCurrentTabCleanupSchedule.minimumSweepSpacing` sweeps and the rest
    /// no-op. The sweep only touches the session when a tab actually expired, so
    /// a quiet scene never persists or stages sync traffic on its account.
    @discardableResult
    func sweepExpiredBrowsingData(now: Date = .now) -> Bool {
        guard family.beginCleanupSweep(at: now) else { return false }
        guard family.executeRecords(.recordsSweep, from: self, at: now) else { return true }
        return true
    }

    @discardableResult
    func sweepExpiredCurrentTabs(now: Date = .now) -> Bool {
        sweepExpiredBrowsingData(now: now)
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
        guard family.executeRecords(.recordsCleanup, in: spaceID, from: self) else { return }
    }

    func restoreArchivedTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        guard
            family.executeRecords(
                .archiveRestore, in: selectedSpaceID, arguments: BrowserSessionArguments.Tab(tabId: id.rawValue),
                from: self)
        else { return }
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
        guard
            family.executeRecords(
                .archiveRestore, in: assignment.spaceID, arguments: BrowserSessionArguments.Tab(tabId: id.rawValue),
                from: self)
        else { return false }
        return true
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
        guard
            family.executeRecords(
                .historyRemoveURL, in: assignment.spaceID,
                arguments: BrowserSessionArguments.HistoryRemoveURL(url: url.absoluteString), from: self)
        else { return false }
        return true
    }

    @discardableResult
    func deleteHistory(
        from startDate: Date,
        until endDate: Date,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard
            family.executeRecords(
                .historyRemoveRange, in: assignment.spaceID,
                arguments: BrowserSessionArguments.HistoryRemoveRange(
                    start: startDate.timeIntervalSinceReferenceDate, end: endDate.timeIntervalSinceReferenceDate),
                from: self)
        else { return false }
        return true
    }
}

// MARK: - Data Retention

extension BrowserStore {
    func updateDataRetentionPreferences(
        _ retention: BrowserSpaceDataRetentionPreferences,
        in spaceID: SpaceID,
        now: Date = .now
    ) {
        guard var preferences = session.space(id: spaceID)?.browsingPreferences,
            preferences.dataRetention != retention
        else {
            return
        }
        preferences.dataRetention = retention
        // Retention is one field of the same Space preferences record every
        // other settings surface writes, so it takes the same core command, and
        // the core's own sweep then applies it.
        guard setCoreSpaceValue(.spaceBrowsingPreferences, preferences, in: spaceID) else { return }
        _ = family.executeRecords(.recordsSweep, in: spaceID, from: self, at: now)
    }
}
