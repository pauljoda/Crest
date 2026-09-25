import CloudKit
import Foundation

/// Runs CloudKit's sync engine over the journal of the session the core keeps
/// in its file. It never reads the journal itself: it asks the core which
/// records wait to upload and for the ones each batch carries, sends the
/// core what the cloud sent and saved as intents, and hears what changed
/// through the core's wake, never through their answers. Every call into the
/// core runs off the main thread.
actor BrowserCloudSyncEngine {
    private let database: @Sendable () -> CKDatabase
    private let core: CrestCore
    private let persistence: any BrowserCloudSyncStatePersisting
    private let codec: BrowserCloudRecordCodec
    private let automaticallySync: Bool
    private let statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)?
    private let activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)?
    private var persistedState: BrowserCloudSyncState
    private var engine: CKSyncEngine?
    private var eventFailureDescription: String?
    private var isPullingSnapshot = false
    private var isStopped = false
    private var activeMerges = 0
    private var failedMerges = 0
    private var needsRecovery: Bool
    private(set) var status: BrowserCloudSyncStatus = .stopped

    init(
        database: @autoclosure @escaping @Sendable () -> CKDatabase,
        core: CrestCore,
        persistence: any BrowserCloudSyncStatePersisting = UserDefaultsBrowserCloudSyncStatePersistence(),
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec()
        self.database = database
        self.core = core
        self.persistence = persistence
        self.automaticallySync = automaticallySync
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        persistedState = try persistence.load() ?? BrowserCloudSyncState()
        needsRecovery = persistedState.requiresFullPull
        if persistedState.reconciliationReason == .legacyRecordConflict {
            persistedState.reconciliationReason = nil
            try persistence.save(persistedState)
        }
        if persistedState.requiresAccountConfirmation {
            status = .pausedForAccountConfirmation
        }
    }

    init(
        configuration: BrowserCloudSyncConfiguration,
        core: CrestCore,
        persistence: any BrowserCloudSyncStatePersisting = UserDefaultsBrowserCloudSyncStatePersistence(),
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec(zoneName: configuration.zoneName)
        self.database = {
            CKContainer(identifier: configuration.containerIdentifier).privateCloudDatabase
        }
        self.core = core
        self.persistence = persistence
        self.automaticallySync = automaticallySync
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        persistedState = try persistence.load() ?? BrowserCloudSyncState()
        needsRecovery = persistedState.requiresFullPull
        if persistedState.reconciliationReason == .legacyRecordConflict {
            persistedState.reconciliationReason = nil
            try persistence.save(persistedState)
        }
        if persistedState.requiresAccountConfirmation {
            status = .pausedForAccountConfirmation
        }
    }

    func start() async {
        isStopped = false
        guard !persistedState.requiresAccountConfirmation else {
            await updateStatus(.pausedForAccountConfirmation)
            return
        }
        do {
            try await clearCompletedConflictResolutionIfNeeded()
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            return
        }
        guard !isStopped else { return }
        let syncEngine = initializedEngine()
        if persistedState.requiresFullPull {
            do {
                _ = try await pullFromICloud()
            } catch {
                await updateStatus(.failed(Self.describe(error)))
                return
            }
        }
        if persistedState.engineStateSerialization == nil {
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(codec.recordZone)
            ])
        }
        await enqueueLocalChanges(on: syncEngine)
        await updateStatus(.idle)
    }

    func stop() async {
        isStopped = true
        await engine?.cancelOperations()
        engine = nil
    }

    func notifyLocalChanges() async {
        guard !isStopped, !persistedState.requiresAccountConfirmation else { return }
        let syncEngine = initializedEngine()
        await enqueueLocalChanges(on: syncEngine)
    }

    func syncNow() async throws {
        guard !isStopped else { throw CancellationError() }
        guard !persistedState.requiresAccountConfirmation else {
            await updateStatus(.pausedForAccountConfirmation)
            return
        }
        let syncEngine = initializedEngine()
        eventFailureDescription = nil
        await updateStatus(.syncing)
        do {
            if persistedState.requiresFullPull {
                _ = try await pullFromICloud()
            }
            try await syncEngine.fetchChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            guard !isStopped else { throw CancellationError() }
            guard !persistedState.requiresAccountConfirmation else {
                await updateStatus(.pausedForAccountConfirmation)
                return
            }
            // `fetchChanges` and `sendChanges` return normally even when the
            // events they drove failed, so reporting success from here would
            // paint "Up to date" over records that never landed.
            if let failure = eventFailureDescription {
                throw BrowserCloudSyncError.remoteChangeNotApplied(failure)
            }
            guard !persistedState.requiresFullPull else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("Pull from iCloud to recover an incomplete download.")
            }
            await enqueueLocalChanges(on: syncEngine)
            try await syncEngine.sendChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            guard !isStopped else { throw CancellationError() }
            if let failure = eventFailureDescription {
                throw BrowserCloudSyncError.remoteChangeNotApplied(failure)
            }
            await updateStatus(.idle)
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            throw error
        }
    }

    func pullFromICloud() async throws -> Int {
        guard !isStopped, !persistedState.requiresAccountConfirmation, !isPullingSnapshot else {
            throw BrowserCloudSyncError.remoteChangeNotApplied("Sync is paused.")
        }
        isPullingSnapshot = true
        defer { isPullingSnapshot = false }
        await updateStatus(.syncing)
        do {
            let snapshot = try await BrowserCloudSnapshotLoader(database: database(), codec: codec).load()
            // An incomplete snapshot must never decide what this device holds;
            // the core refuses one whose payloads it cannot all read.
            guard snapshot.unreadable == 0 else {
                throw BrowserCloudSyncError.remoteChangeNotApplied(
                    "Some iCloud records could not be read. Update Crest on all devices and try again.")
            }
            let records = snapshot.records
            guard !isStopped, !persistedState.requiresAccountConfirmation else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("The iCloud account changed during the download.")
            }
            try await mergeDownloadedRecords(records, isFullSnapshot: true)
            guard !persistedState.requiresFullPull else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("Some incoming changes still need to be recovered.")
            }
            eventFailureDescription = nil
            isPullingSnapshot = false
            await enqueueLocalChanges(on: initializedEngine())
            await activityHandler?(.fetched(recordCount: records.count))
            await updateStatus(.idle)
            return records.count
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            throw error
        }
    }

    /// Write the recovery marker before applying content. State-update events
    /// may persist a newer cursor even when this merge fails or the app exits.
    /// A full snapshot is refused whole when the core cannot read all of it.
    /// Answers the records the core left out.
    @discardableResult
    func mergeDownloadedRecords(
        _ records: [SyncRecord],
        isFullSnapshot: Bool = false
    ) async throws -> SyncRecordsSkipped? {
        let failuresBeforeMerge = failedMerges
        activeMerges += 1
        let receipts: [Change]
        do {
            persistedState.requiresFullPull = true
            try persistence.save(persistedState)
            if isFullSnapshot {
                receipts = try await deliver(MergeCloudSnapshot(records: records))
            } else {
                receipts = try await deliver(MergeSyncRecords(records: records))
            }
            guard !isStopped, !persistedState.requiresAccountConfirmation else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("Sync stopped while applying downloaded content.")
            }
            if isFullSnapshot, failedMerges == failuresBeforeMerge {
                needsRecovery = false
            }
        } catch {
            activeMerges -= 1
            failedMerges += 1
            needsRecovery = true
            persistedState.requiresFullPull = true
            if !isStopped { try? persistence.save(persistedState) }
            throw error
        }
        activeMerges -= 1
        persistedState.requiresFullPull = needsRecovery || activeMerges > 0
        do {
            try persistence.save(persistedState)
        } catch {
            needsRecovery = true
            persistedState.requiresFullPull = true
            throw error
        }
        return receipts.lazy.compactMap { receipt -> SyncRecordsSkipped? in
            if case .syncRecordsSkipped(let skipped) = receipt { return skipped }
            return nil
        }.first
    }

    /// Account switches are deliberately paused. Calling this is the explicit user
    /// decision to upload this device's local Spaces into the currently signed-in account.
    func resumeAfterAccountChange() async throws {
        persistedState = BrowserCloudSyncState()
        needsRecovery = false
        try persistence.save(persistedState)
        engine = nil
        await updateStatus(.stopped)
        await start()
    }

    func process(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        guard !isStopped else { return }
        do {
            switch event {
            case .stateUpdate(let event):
                persistedState.engineStateSerialization = event.stateSerialization
                try persistence.save(persistedState)
            case .accountChange(let event):
                if try handleAccountChange(event) {
                    await activityHandler?(.accountChanged)
                }
            case .fetchedRecordZoneChanges(let event):
                try await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)
            case .fetchedDatabaseChanges(let event):
                try await handleFetchedDatabaseChanges(event, syncEngine: syncEngine)
            case .sentRecordZoneChanges(let event):
                try await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
            case .willFetchChanges,
                .willFetchRecordZoneChanges,
                .didFetchRecordZoneChanges,
                .didFetchChanges,
                .willSendChanges,
                .didSendChanges,
                .sentDatabaseChanges:
                break
            @unknown default:
                break
            }
        } catch {
            eventFailureDescription = Self.describe(error)
            await updateStatus(.failed(Self.describe(error)))
        }
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = .zoneIDs(context.options.scope.contains(codec.recordZoneID) ? [codec.recordZoneID] : [])
        return options
    }

    func makeRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !isStopped, !persistedState.requiresAccountConfirmation,
            !persistedState.requiresFullPull, !isPullingSnapshot
        else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            switch $0 {
            case .saveRecord(let id), .deleteRecord(let id):
                return id.zoneID == codec.recordZoneID && context.options.scope.contains($0)
            @unknown default:
                return false
            }
        }
        // Every stage the core queued settles first, so the batch carries the
        // newest records. A core that refuses to answer uploads nothing.
        await core.settleSync()
        let source = BrowserCloudUploadSource(
            core: core, codec: codec,
            saves: changes.compactMap {
                guard case .saveRecord(let id) = $0 else { return nil }
                return id
            })
        do { try await source.prepare() } catch { return nil }
        guard !isStopped, !persistedState.requiresAccountConfirmation,
            !persistedState.requiresFullPull, !isPullingSnapshot
        else { return nil }
        let systemFields = persistedState.systemFields
        let codec = codec
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            switch await source.upload(for: recordID) {
            case .record(let record):
                // A record whose server copy a newer build wrote stays
                // pending, skipped.
                return try? codec.record(for: record, reusing: systemFields.record(for: recordID))
            case .gone:
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            case .skipped:
                return nil
            }
        }
    }

    private func initializedEngine() -> CKSyncEngine {
        if let engine { return engine }
        var configuration = CKSyncEngine.Configuration(
            database: database(),
            stateSerialization: persistedState.engineStateSerialization,
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        let result = CKSyncEngine(configuration)
        engine = result
        return result
    }

    private func enqueueLocalChanges(on syncEngine: CKSyncEngine) async {
        // A core that refuses to answer queues nothing; the next journal change
        // asks again.
        guard let pending = try? await pendingUploads() else { return }
        guard !isStopped, !persistedState.requiresAccountConfirmation else { return }
        syncEngine.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(codec.recordID(for: $0)) })
    }

    private func clearCompletedConflictResolutionIfNeeded() async throws {
        let pending = try await pendingUploads()
        let resolution = BrowserCloudConflictResolutionPolicy.resolutionAfterRestart(
            persistedResolution: persistedState.conflictResolution,
            hasPendingUploads: !pending.isEmpty
        )
        guard resolution != persistedState.conflictResolution else { return }
        persistedState.conflictResolution = resolution
        try persistence.save(persistedState)
    }

    /// The records the core's journal holds waiting to upload, once every
    /// stage the core queued has settled.
    private func pendingUploads() async throws -> [SyncRecordReference] {
        await core.settleSync()
        return try core.query(PendingUploads()).records
    }

    /// Sends the core an intent from the cloud on a utility thread: the core
    /// computes it on the thread that sends it, never the main thread, and what
    /// it changed reaches the main thread through its wake.
    @discardableResult
    private func deliver(_ intent: some CloudSyncIntent) async throws -> [Change] {
        let core = core
        return try await Task.detached(priority: .utility) { try core.deliver(intent) }.value
    }

    /// What the person is told of a failure: a refusal in the core's own words,
    /// anything else as it describes itself.
    private static func describe(_ error: any Error) -> String {
        (error as? Rejection)?.explanation ?? String(describing: error)
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        guard !persistedState.requiresAccountConfirmation else { return }
        // Each record is read on its own, so one this build cannot read never
        // costs the batch it arrived in: the change token advances whether or
        // not the records were applied, so a batch abandoned that way would
        // never be offered again.
        var records: [SyncRecord] = []
        var unreadable = 0
        var fromNewerBuild = 0
        for modification in event.modifications {
            guard modification.record.recordID.zoneID == codec.recordZoneID else { continue }
            persistedState.systemFields.update(with: modification.record)
            if let record = codec.syncRecord(from: modification.record) {
                records.append(record)
            } else {
                unreadable += 1
            }
        }
        if !records.isEmpty {
            if BrowserCloudConflictResolutionPolicy.shouldMergeFetchedContent(
                resolution: persistedState.conflictResolution
            ), let skipped = try await mergeDownloadedRecords(records) {
                unreadable += skipped.unreadable
                fromNewerBuild += skipped.fromNewerBuild
            }
            await enqueueLocalChanges(on: syncEngine)
            let applied = records.count - unreadable - fromNewerBuild
            if !persistedState.requiresFullPull, applied > 0 {
                await activityHandler?(.fetched(recordCount: applied))
            }
        }
        if unreadable + fromNewerBuild > 0 {
            // A newer build of Crest wrote some of these; the signal tells the
            // person why one device is missing something the others have.
            let skipped = BrowserCloudSyncActivity.skippedRecords(
                count: unreadable + fromNewerBuild,
                requiresAppUpdate: fromNewerBuild > 0
            )
            await activityHandler?(skipped)
        }

        // A record somebody deleted from iCloud is saved again; a later batch
        // drops the save of one the journal no longer holds.
        for deletion in event.deletions where deletion.recordID.zoneID == codec.recordZoneID {
            persistedState.systemFields.remove(recordName: deletion.recordID.recordName)
            if codec.reference(for: deletion.recordID) != nil {
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
            }
        }
        try persistence.save(persistedState)
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        guard !persistedState.requiresAccountConfirmation else { return }
        guard
            let deletion = event.deletions.first(where: {
                $0.zoneID == codec.recordZoneID
            })
        else { return }
        persistedState.systemFields = BrowserCloudRecordSystemFields()
        if Self.restoresLocalRecords(afterZoneDeletion: deletion.reason) {
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(codec.recordZone)
            ])
            await enqueueLocalChanges(on: syncEngine)
        } else {
            // Somebody removed Crest's data from iCloud on purpose. Recreating
            // the zone and re-uploading every local record would undo that
            // before they finished reading the confirmation sheet. Local Spaces
            // stay untouched; the next deliberate start decides what to upload.
            persistedState.engineStateSerialization = nil
            await activityHandler?(.cloudDataRemoved)
        }
        try persistence.save(persistedState)
    }

    /// Whether a zone that stopped existing should be rebuilt from local records.
    ///
    /// `encryptedDataReset` means iCloud discarded the encrypted contents while
    /// the person kept their data, so this device is the surviving copy. A
    /// deletion or a purge is a decision, and Crest does not overrule it.
    static func restoresLocalRecords(
        afterZoneDeletion reason: CKDatabase.DatabaseChange.Deletion.Reason
    ) -> Bool {
        switch reason {
        case .encryptedDataReset:
            true
        case .deleted, .purged:
            false
        @unknown default:
            false
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        var uploaded: [UploadedRecord] = []
        for record in event.savedRecords where record.recordID.zoneID == codec.recordZoneID {
            persistedState.systemFields.update(with: record)
            if let saved = codec.uploadedRecord(record) { uploaded.append(saved) }
        }
        if !uploaded.isEmpty {
            try await deliver(AcknowledgeUploads(records: uploaded))
            if !persistedState.requiresFullPull {
                await activityHandler?(.uploaded(recordCount: uploaded.count))
            }
        }

        for failure in event.failedRecordSaves {
            let recordID = failure.record.recordID
            guard recordID.zoneID == codec.recordZoneID else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.serverRecord {
                    persistedState.systemFields.update(with: serverRecord)
                    if persistedState.conflictResolution == .useThisDevice {
                        syncEngine.state.add(
                            pendingRecordZoneChanges: [.saveRecord(recordID)]
                        )
                        continue
                    }
                    // The server copy cannot be applied here when this build
                    // cannot read it, usually a newer schema. Leaving the local
                    // save pending retries the same conflict forever and poisons
                    // every atomic batch it rides in; yield until the app can
                    // read it.
                    let merged = codec.syncRecord(from: serverRecord)
                    let skipped: SyncRecordsSkipped? =
                        if let merged { try await mergeDownloadedRecords([merged]) } else {
                            SyncRecordsSkipped(unreadable: 1, fromNewerBuild: 0)
                        }
                    if let skipped, skipped.unreadable + skipped.fromNewerBuild > 0 {
                        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                        await activityHandler?(
                            .skippedRecords(count: 1, requiresAppUpdate: skipped.fromNewerBuild > 0))
                        continue
                    }
                    // CloudKit requires the server copy's change tag as the
                    // retry base. The journal deterministically reconciles the
                    // semantic values, then the refreshed system fields let the
                    // next save target that server version.
                    await enqueueLocalChanges(on: syncEngine)
                }
            case .zoneNotFound:
                persistedState.systemFields.remove(recordName: recordID.recordName)
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(codec.recordZone)
                ])
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                persistedState.systemFields.remove(recordName: recordID.recordName)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .networkFailure,
                .networkUnavailable,
                .zoneBusy,
                .serviceUnavailable,
                .notAuthenticated,
                .operationCancelled:
                break
            default:
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }
        if persistedState.conflictResolution == .useThisDevice, (try? await pendingUploads())?.isEmpty == true {
            persistedState.conflictResolution = nil
        }
        try persistence.save(persistedState)
    }

    private func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange
    ) throws -> Bool {
        let transition: BrowserCloudAccountTransition
        switch event.changeType {
        case .switchAccounts:
            transition = .switchAccounts
        case .signOut:
            transition = .signOut
        case .signIn:
            transition = .signIn
        @unknown default:
            transition = .unknown
        }

        let requiresReconciliation =
            BrowserCloudAccountChangePolicy
            .requiresReconciliation(
                for: transition,
                alreadyRequiresReconciliation:
                    persistedState.requiresAccountConfirmation
            )
        guard requiresReconciliation else { return false }

        switch transition {
        case .switchAccounts, .signOut, .unknown:
            persistedState.reconciliationReason = .accountChange
            status = .pausedForAccountConfirmation
            try persistence.save(persistedState)
            return true
        case .signIn:
            status = .pausedForAccountConfirmation
            return true
        }
    }

    private func updateStatus(_ newStatus: BrowserCloudSyncStatus) async {
        status = newStatus
        await statusHandler?(newStatus)
    }
}
