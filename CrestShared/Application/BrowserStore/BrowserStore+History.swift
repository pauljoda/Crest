import Foundation

// MARK: - History and Cleanup

extension BrowserStore {
    func recordVisit(url: URL, title: String?) {
        guard selectedSpace != nil else { return }
        let spaceID = session.selectedSpaceID
        guard recordSessionVisit(url: url, title: title, in: spaceID) else { return }
        persist(syncUrgency: .coalesced, scope: .history(in: spaceID))
    }

    func recordVisit(url: URL, title: String?, in spaceID: SpaceID) {
        guard recordSessionVisit(url: url, title: title, in: spaceID) else { return }
        persist(syncUrgency: .coalesced, scope: .history(in: spaceID))
    }

    @discardableResult
    func recordVisit(
        url: URL,
        title: String?,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard recordSessionVisit(url: url, title: title, in: assignment.spaceID) else { return false }
        persist(
            syncUrgency: .coalesced,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    private func recordSessionVisit(url: URL, title: String?, in spaceID: SpaceID) -> Bool {
        family.executeRecords("history.visit", in: spaceID, arguments: [
            "url": url.absoluteString, "title": title as Any? ?? NSNull()
        ], from: self)
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
        guard let value = BrowserCoreSessionEditing.tabValue(tab),
            family.execute("transient.archive", in: assignment.spaceID,
                arguments: ["requestId": requestID.uuidString, "tab": value], from: self, at: date) != nil
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    func clearHistory() {
        guard selectedSpace != nil else { return }
        clearHistory(in: session.selectedSpaceID)
    }

    func clearHistory(in spaceID: SpaceID) {
        guard family.executeRecords("history.clear", in: spaceID, from: self) else { return }
        persist(deletionReason: .explicitDelete, scope: .history(in: spaceID))
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard family.executeRecords("history.clear", in: assignment.spaceID, from: self) else { return false }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    func cleanupCurrentTabs() {
        guard family.executeRecords("records.cleanup", from: self) else { return }
        persist(deletionReason: .retention, scope: .core)
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
        guard family.executeRecords("records.sweep", from: self, at: now) else { return true }
        persist(deletionReason: .retention, scope: .everything)
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
        guard family.executeRecords("records.cleanup", in: spaceID, from: self) else { return }
        persist(deletionReason: .retention, scope: .core)
    }

    func restoreArchivedTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        guard family.executeRecords("archive.restore", in: session.selectedSpaceID,
            arguments: ["tabId": id.rawValue.uuidString], from: self) else { return }
        persist(deletionReason: .superseded, scope: .core)
    }

    @discardableResult
    func restoreArchivedTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.archivedTabs.contains(where: { $0.id == id })
        else { return false }
        guard family.executeRecords("archive.restore", in: assignment.spaceID,
            arguments: ["tabId": id.rawValue.uuidString], from: self) else { return false }
        persist(deletionReason: .superseded, scope: .core)
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
        guard family.executeRecords("history.remove_url", in: assignment.spaceID,
            arguments: ["url": url.absoluteString], from: self) else { return false }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    @discardableResult
    func deleteHistory(
        from startDate: Date,
        until endDate: Date,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        guard family.executeRecords("history.remove_range", in: assignment.spaceID, arguments: [
            "start": startDate.timeIntervalSinceReferenceDate, "end": endDate.timeIntervalSinceReferenceDate
        ], from: self) else { return false }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
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
        // other settings surface writes, so it takes the same core command.
        guard setCoreSpaceValue("space.browsing_preferences", preferences, in: spaceID) else { return }
        let removedRecords = family.applyDataRetentionPolicies(at: now, from: self)
        persist(
            deletionReason: removedRecords ? .retention : .superseded,
            scope: removedRecords ? .everything : .core
        )
    }
}
