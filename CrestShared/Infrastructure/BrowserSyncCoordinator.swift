import Foundation

final class BrowserSyncCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var storedJournal: BrowserSyncJournal
    let status: BrowserSyncCoordinatorStatus
    private let persistence: any BrowserSyncJournalPersisting

    var journal: BrowserSyncJournal {
        lock.withLock { storedJournal }
    }

    init(
        persistence: any BrowserSyncJournalPersisting,
        deviceID: UUID = UUID(),
        preferences: BrowserSyncPreferences = .default
    ) {
        self.persistence = persistence
        do {
            storedJournal =
                try persistence.load()
                ?? BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .ready
        } catch {
            storedJournal = BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .recoveredCorruptLocalJournal
        }
    }

    func stage(
        session: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now
    ) throws {
        try commit { journal in
            try journal.stage(
                session: session,
                deletionReason: deletionReason,
                at: date
            )
        }
    }

    func stageInBackground(
        session: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now
    ) async throws {
        try await Task.detached(priority: .utility) {
            try self.stage(
                session: session,
                deletionReason: deletionReason,
                at: date
            )
        }.value
    }

    func merge(
        remoteRecords: [BrowserSyncRecord],
        into localSession: BrowserSession,
        at date: Date = .now
    ) throws -> BrowserSession {
        try commit { journal in
            try journal.merge(remoteRecords)
            var materialized = try journal.materializedSession(applyingTo: localSession)
            let removedRecords = materialized.applyDataRetentionPolicies(now: date)
            try journal.stage(
                session: materialized,
                deletionReason: removedRecords ? .retention : .superseded,
                at: date
            )
            return materialized
        }
    }

    func prepareToOverwriteCloud(
        with session: BrowserSession,
        remoteRecords: [BrowserSyncRecord],
        at date: Date = .now
    ) throws {
        try commit { journal in
            try journal.prepareToOverwriteCloud(
                with: session,
                remoteRecords: remoteRecords,
                at: date
            )
        }
    }

    func replaceLocalWithCloud(
        _ remoteRecords: [BrowserSyncRecord],
        replacing localSession: BrowserSession,
        at date: Date = .now
    ) throws -> BrowserSession {
        try commit { journal in
            try journal.replaceWithCloud(remoteRecords)
            var materialized =
                if remoteRecords.isEmpty {
                    Self.blankSession()
                } else {
                    try journal.materializedSession(applyingTo: localSession)
                }
            let removedRecords = materialized.applyDataRetentionPolicies(now: date)
            if removedRecords {
                try journal.stage(
                    session: materialized,
                    deletionReason: .retention,
                    at: date
                )
            }
            return materialized
        }
    }

    private static func blankSession() -> BrowserSession {
        let tab = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Space 1",
            symbol: "square.grid.2x2.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        try commit { journal in
            journal.markUploaded(recordIDs)
        }
    }

    func markUploaded(_ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]) throws {
        try commit { journal in
            journal.markUploaded(acknowledgedVersions)
        }
    }

    private func commit<Result>(
        _ mutation: (inout BrowserSyncJournal) throws -> Result
    ) throws -> Result {
        try lock.withLock {
            var candidate = storedJournal
            let result = try mutation(&candidate)
            try persistence.save(candidate)
            storedJournal = candidate
            return result
        }
    }
}
