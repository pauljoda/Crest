import CloudKit
import Foundation

actor BrowserCloudSyncEngine {
    private let database: @Sendable () -> CKDatabase
    private let gateway: any BrowserCloudSyncModelGateway
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
        gateway: any BrowserCloudSyncModelGateway,
        persistence: any BrowserCloudSyncStatePersisting = UserDefaultsBrowserCloudSyncStatePersistence(),
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec()
        self.database = database
        self.gateway = gateway
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
        gateway: any BrowserCloudSyncModelGateway,
        persistence: any BrowserCloudSyncStatePersisting = UserDefaultsBrowserCloudSyncStatePersistence(),
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec(zoneName: configuration.zoneName)
        self.database = {
            CKContainer(identifier: configuration.containerIdentifier).privateCloudDatabase
        }
        self.gateway = gateway
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
            await updateStatus(.failed(String(describing: error)))
            return
        }
        guard !isStopped else { return }
        let syncEngine = initializedEngine()
        if persistedState.requiresFullPull {
            do {
                _ = try await pullFromICloud()
            } catch {
                await updateStatus(.failed(String(describing: error)))
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
                throw BrowserSyncError.remoteChangeNotApplied(failure)
            }
            guard !persistedState.requiresFullPull else {
                throw BrowserSyncError.remoteChangeNotApplied("Pull from iCloud to recover an incomplete download.")
            }
            await enqueueLocalChanges(on: syncEngine)
            try await syncEngine.sendChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            guard !isStopped else { throw CancellationError() }
            if let failure = eventFailureDescription {
                throw BrowserSyncError.remoteChangeNotApplied(failure)
            }
            await updateStatus(.idle)
        } catch {
            await updateStatus(.failed(String(describing: error)))
            throw error
        }
    }

    func pullFromICloud() async throws -> Int {
        guard !isStopped, !persistedState.requiresAccountConfirmation, !isPullingSnapshot else {
            throw BrowserSyncError.remoteChangeNotApplied("Sync is paused.")
        }
        isPullingSnapshot = true
        defer { isPullingSnapshot = false }
        await updateStatus(.syncing)
        do {
            let records = try await BrowserCloudSnapshotLoader(database: database(), codec: codec)
                .load(requiresCompleteSnapshot: true)
            guard !isStopped, !persistedState.requiresAccountConfirmation else {
                throw BrowserSyncError.remoteChangeNotApplied("The iCloud account changed during the download.")
            }
            try await mergeDownloadedRecords(records, isFullSnapshot: true)
            guard !persistedState.requiresFullPull else {
                throw BrowserSyncError.remoteChangeNotApplied("Some incoming changes still need to be recovered.")
            }
            eventFailureDescription = nil
            isPullingSnapshot = false
            await enqueueLocalChanges(on: initializedEngine())
            await activityHandler?(.fetched(recordCount: records.count))
            await updateStatus(.idle)
            return records.count
        } catch {
            await updateStatus(.failed(String(describing: error)))
            throw error
        }
    }

    /// Write the recovery marker before applying content. State-update events
    /// may persist a newer cursor even when this merge fails or the app exits.
    func mergeDownloadedRecords(
        _ records: [BrowserSyncRecord],
        isFullSnapshot: Bool = false
    ) async throws {
        let failuresBeforeMerge = failedMerges
        activeMerges += 1
        do {
            persistedState.requiresFullPull = true
            try persistence.save(persistedState)
            try await gateway.mergeCloudSyncRecords(records)
            guard !isStopped, !persistedState.requiresAccountConfirmation else {
                throw BrowserSyncError.remoteChangeNotApplied("Sync stopped while applying downloaded content.")
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
            eventFailureDescription = String(describing: error)
            await updateStatus(.failed(String(describing: error)))
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
        // A journal this build cannot read uploads nothing.
        guard let records = try? await gateway.cloudSyncRecords() else { return nil }
        guard !isStopped, !persistedState.requiresAccountConfirmation,
            !persistedState.requiresFullPull, !isPullingSnapshot
        else { return nil }
        var recordsByName: [String: BrowserSyncRecord] = [:]
        for record in records {
            recordsByName[record.id.recordName] = record
        }
        let immutableRecordsByName = recordsByName
        let systemFields = persistedState.systemFields
        let codec = codec

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let source = immutableRecordsByName[recordID.recordName] else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return try? codec.encode(source, reusing: systemFields.record(for: recordID))
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
        // A journal this build cannot read queues nothing; the next journal
        // change tries again.
        guard let pendingIDs = try? await gateway.cloudSyncPendingRecordIDs() else { return }
        guard !isStopped, !persistedState.requiresAccountConfirmation else { return }
        let changes = pendingIDs.map { id in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(
                CKRecord.ID(recordName: id.recordName, zoneID: codec.recordZoneID)
            )
        }
        syncEngine.state.add(pendingRecordZoneChanges: changes)
    }

    private func clearCompletedConflictResolutionIfNeeded() async throws {
        let pendingIDs = try await gateway.cloudSyncPendingRecordIDs()
        let resolution = BrowserCloudConflictResolutionPolicy.resolutionAfterRestart(
            persistedResolution: persistedState.conflictResolution,
            hasPendingUploads: !pendingIDs.isEmpty
        )
        guard resolution != persistedState.conflictResolution else { return }
        persistedState.conflictResolution = resolution
        try persistence.save(persistedState)
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        guard !persistedState.requiresAccountConfirmation else { return }
        var fetchedRecords: [CKRecord] = []
        for modification in event.modifications {
            guard modification.record.recordID.zoneID == codec.recordZoneID else { continue }
            fetchedRecords.append(modification.record)
            persistedState.systemFields.update(with: modification.record)
        }
        let batch = Self.fetchedBatch(decoding: fetchedRecords, using: codec)
        if !batch.records.isEmpty {
            if BrowserCloudConflictResolutionPolicy.shouldMergeFetchedContent(
                resolution: persistedState.conflictResolution
            ) {
                try await mergeDownloadedRecords(batch.records)
            }
            await enqueueLocalChanges(on: syncEngine)
            if !persistedState.requiresFullPull {
                await activityHandler?(.fetched(recordCount: batch.records.count))
            }
        }
        let skippedCount =
            batch.undecodableRecordNames.count + batch.newerSchemaRecordNames.count
        if skippedCount > 0 {
            let skipped = BrowserCloudSyncActivity.skippedRecords(
                count: skippedCount,
                requiresAppUpdate: !batch.newerSchemaRecordNames.isEmpty
            )
            await activityHandler?(skipped)
        }

        if !event.deletions.isEmpty {
            let localRecords = try await gateway.cloudSyncRecords()
            let localNames = Set(localRecords.map { $0.id.recordName })
            for deletion in event.deletions where deletion.recordID.zoneID == codec.recordZoneID {
                persistedState.systemFields.remove(recordName: deletion.recordID.recordName)
                if localNames.contains(deletion.recordID.recordName) {
                    syncEngine.state.add(pendingRecordZoneChanges: [
                        .saveRecord(deletion.recordID)
                    ])
                }
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

    /// Decodes each record on its own so one unreadable record cannot cost the
    /// batch it arrived in.
    ///
    /// One record CloudKit cannot turn into a journal record — a corrupt payload,
    /// or a record a newer build of Crest wrote — used to fail the whole event.
    /// The change token advances whether or not the records were applied, so a
    /// batch abandoned that way is never offered again.
    static func fetchedBatch(
        decoding records: [CKRecord],
        using codec: BrowserCloudRecordCodec = BrowserCloudRecordCodec()
    ) -> (
        records: [BrowserSyncRecord],
        undecodableRecordNames: [String],
        newerSchemaRecordNames: [String]
    ) {
        var decoded: [BrowserSyncRecord] = []
        var undecodable: [String] = []
        var newerSchema: [String] = []
        for record in records {
            do {
                decoded.append(try codec.decode(record))
            } catch BrowserSyncError.unsupportedSchema(let schema)
                where schema > BrowserCloudRecordCodec.currentSchemaVersion
            {
                // A newer build of Crest wrote this. Leaving it alone keeps the
                // rest of the batch, and the signal tells the person why one
                // device is missing something the others have.
                newerSchema.append(record.recordID.recordName)
            } catch {
                undecodable.append(record.recordID.recordName)
            }
        }
        return (decoded, undecodable, newerSchema)
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        var uploaded: [BrowserSyncRecordID: BrowserSyncVersion] = [:]
        for record in event.savedRecords where record.recordID.zoneID == codec.recordZoneID {
            persistedState.systemFields.update(with: record)
            if let decoded = try? codec.decode(record) {
                uploaded[decoded.id] = decoded.version
            }
        }
        if !uploaded.isEmpty {
            try await gateway.markCloudSyncRecordsUploaded(uploaded)
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
                    let batch = Self.fetchedBatch(
                        decoding: [serverRecord],
                        using: codec
                    )
                    guard let decoded = batch.records.first else {
                        // The server copy cannot be applied here — usually a
                        // newer schema. Leaving the local save pending retries
                        // the same conflict forever and poisons every atomic
                        // batch it rides in; yield until the app can decode it.
                        syncEngine.state.remove(
                            pendingRecordZoneChanges: [.saveRecord(recordID)]
                        )
                        let skipped = BrowserCloudSyncActivity.skippedRecords(
                            count: 1,
                            requiresAppUpdate: !batch.newerSchemaRecordNames.isEmpty
                        )
                        await activityHandler?(skipped)
                        continue
                    }
                    // CloudKit requires the server copy's change tag as the
                    // retry base. The journal deterministically reconciles the
                    // semantic values, then the refreshed system fields let the
                    // next save target that server version.
                    try await mergeDownloadedRecords([decoded])
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
        if persistedState.conflictResolution == .useThisDevice,
            (try? await gateway.cloudSyncPendingRecordIDs())?.isEmpty == true
        {
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
