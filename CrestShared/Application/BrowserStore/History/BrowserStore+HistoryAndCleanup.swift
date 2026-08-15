import Foundation

extension BrowserStore {
    func recordVisit(url: URL, title: String?) {
        guard selectedSpace != nil else { return }
        let spaceID = session.selectedSpaceID
        session.recordVisit(url: url, title: title)
        persist(syncUrgency: .coalesced, scope: .history(in: spaceID))
    }

    func recordVisit(url: URL, title: String?, in spaceID: SpaceID) {
        session.recordVisit(url: url, title: title, in: spaceID)
        persist(syncUrgency: .coalesced, scope: .history(in: spaceID))
    }

    @discardableResult
    func recordVisit(
        url: URL,
        title: String?,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        session.recordVisit(url: url, title: title, in: assignment.spaceID)
        persist(
            syncUrgency: .coalesced,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    func archiveTransientPage(url: URL, title: String?, in spaceID: SpaceID) {
        session.archiveTransientPage(url: url, title: title, in: spaceID)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    @discardableResult
    func archiveTransientPage(
        url: URL,
        title: String?,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        session.archiveTransientPage(
            url: url,
            title: title,
            in: assignment.spaceID
        )
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    func clearHistory() {
        guard selectedSpace != nil else { return }
        clearHistory(in: session.selectedSpaceID)
    }

    func clearHistory(in spaceID: SpaceID) {
        guard session.clearHistory(in: spaceID) else { return }
        persist(deletionReason: .explicitDelete, scope: .history(in: spaceID))
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.clearHistory(in: assignment.spaceID)
        else { return false }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    func cleanupCurrentTabs() {
        session.cleanupCurrentTabsUsingSpacePreferences()
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
        var swept = session
        swept.cleanupCurrentTabsUsingSpacePreferences(now: now)
        let removedStoredRecords = swept.applyDataRetentionPolicies(now: now)
        guard swept != session else { return true }
        session = swept
        persist(
            deletionReason: .retention,
            scope: removedStoredRecords ? .everything : .core
        )
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
        session.cleanupCurrentTabs(in: spaceID)
        persist(deletionReason: .retention, scope: .core)
    }

    func restoreArchivedTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        session.restoreArchivedTab(id)
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
        session.restoreArchivedTab(id)
        persist(deletionReason: .superseded, scope: .core)
        return true
    }
}
