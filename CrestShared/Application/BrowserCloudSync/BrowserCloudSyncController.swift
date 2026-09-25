import Foundation
import Observation

/// Brings sync up against the signed-in iCloud account and keeps it running:
/// account checks, the first launch's seed, reconciling with an account it has
/// not synced with, conflict choices and retries. It reads what the stored
/// session's journal holds from the core's published state, asks the core
/// how the cloud's content compares, and sends the core the person's choices
/// off the main thread; it never reads the journal itself.
@Observable
@MainActor
final class BrowserCloudSyncController {
    private(set) var accountState: BrowserCloudAccountState = .checking
    private(set) var phase: BrowserCloudSyncPhase
    private(set) var lastAttemptAt: Date?
    private(set) var lastSuccessAt: Date?
    private(set) var lastFetchedRecordCount = 0
    private(set) var lastUploadedRecordCount = 0
    private(set) var observedCloudRecordCount: Int?
    private(set) var errorDescription: String?
    private(set) var conflict: BrowserCloudSyncConflictSummary?
    private(set) var skippedRecordCount = 0
    private(set) var requiresAppUpdate = false
    private(set) var cloudDataWasRemoved = false
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            preferences.saveIsEnabled(isEnabled)
            Task { await enabledStateDidChange() }
        }
    }

    let containerIdentifier: String?

    @ObservationIgnored private let core: CrestCore
    @ObservationIgnored private let configuration: BrowserCloudSyncConfiguration?
    @ObservationIgnored private let preferences: any BrowserCloudSyncPreferences
    @ObservationIgnored private let remoteService: (any BrowserCloudSyncRemoteService)?
    @ObservationIgnored private let transportFactory: (any BrowserCloudSyncTransportFactory)?
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private var transport: (any BrowserCloudSyncTransport)?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var accountRestartRequested = false
    @ObservationIgnored private var startGeneration = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempts = 0
    @ObservationIgnored private var accountObservation: (any NSObjectProtocol)?

    /// Crest only retries a launch that could not reach iCloud a few times. A
    /// signed-out account heals through `accountAvailabilityDidChange` instead of
    /// through polling.
    private static let maximumRetryAttempts = 3

    /// How many records the stored session's journal holds, as the core last
    /// published it.
    var localRecordCount: Int { core.state.syncJournal?.records ?? 0 }

    /// How many of them wait to upload, as the core last published it.
    var pendingUploadCount: Int { core.state.syncJournal?.pendingRecords ?? 0 }

    /// Why this device's changes cannot reach sync: the core could not stage
    /// the latest edits, or could not save them.
    var localErrorDescription: String? {
        core.state.syncStagingFailure.map { String(localized: $0.title) } ?? core.state.storageFailureDescription
    }

    init(
        core: CrestCore,
        configuration: BrowserCloudSyncConfiguration?,
        preferences: any BrowserCloudSyncPreferences,
        remoteService: (any BrowserCloudSyncRemoteService)?,
        transportFactory: (any BrowserCloudSyncTransportFactory)?,
        retryDelay: Duration = .seconds(30)
    ) {
        self.core = core
        self.configuration = configuration
        self.preferences = preferences
        self.remoteService = remoteService
        self.transportFactory = transportFactory
        self.retryDelay = retryDelay
        containerIdentifier = configuration?.containerIdentifier
        let initiallyEnabled = preferences.loadIsEnabled() ?? true
        isEnabled = initiallyEnabled
        phase = initiallyEnabled ? .checking : .disabled
    }

    /// Brings sync up against the account that is signed in right now.
    ///
    /// Every step after the first suspension re-reads `isEnabled` and the start
    /// generation. Turning sync off mid-launch discards the transport and reports
    /// Off, so a start that resumed afterwards and carried on would leave a live
    /// engine syncing behind an interface that says it is not.
    func start() async {
        guard isEnabled, !isRunning, transport == nil else { return }
        isRunning = true
        startGeneration += 1
        let generation = startGeneration
        defer {
            isRunning = false
            scheduleAccountRestartIfNeeded()
            scheduleRetryIfNeeded()
        }
        guard configuration != nil else {
            phase = .failed("Crest’s CloudKit container is not configured.")
            accountState = .couldNotDetermine
            return
        }
        guard let remoteService, let transportFactory else {
            phase = .failed("Crest’s CloudKit container is not configured.")
            accountState = .couldNotDetermine
            return
        }
        guard await remoteService.hasRequiredEntitlement() else {
            guard isCurrentStart(generation) else { return }
            phase = .failed("iCloud Sync is unavailable in this build of Crest.")
            accountState = .couldNotDetermine
            errorDescription = "The app is missing access to Crest’s CloudKit container."
            return
        }
        guard isCurrentStart(generation) else { return }

        phase = .checking
        errorDescription = nil
        lastAttemptAt = .now

        do {
            let state = try await remoteService.accountState()
            guard isCurrentStart(generation) else { return }
            accountState = state
            guard accountState == .available else {
                phase = .waitingForAccount
                return
            }

            try await replaceDisposableSeedStateFromCloudIfNeeded(
                using: remoteService
            )
            guard isCurrentStart(generation) else { return }
            if try preferences.requiresAccountConfirmation() {
                try await prepareAccountReconciliation(
                    remoteService: remoteService,
                    transportFactory: transportFactory,
                    generation: generation
                )
                return
            }
            try await startTransport(
                using: transportFactory,
                generation: generation
            )
        } catch {
            guard isCurrentStart(generation) else { return }
            fail(error)
        }
    }

    func syncNow() async {
        guard isEnabled, conflict == nil, !isRunning else { return }
        if transport == nil {
            await start()
            return
        }
        isRunning = true
        let generation = startGeneration
        defer {
            isRunning = false
            scheduleAccountRestartIfNeeded()
            scheduleRetryIfNeeded()
        }
        lastAttemptAt = .now
        do {
            phase = .syncing
            try await transport?.syncNow()
            guard isCurrentStart(generation) else { return }
            guard !accountRestartRequested else { return }
            guard conflict == nil else {
                phase = .needsReconciliation
                return
            }
            recordSuccess()
        } catch {
            guard isCurrentStart(generation) else { return }
            fail(error)
        }
    }

    func localChangesDidStage() async {
        guard isEnabled, conflict == nil else { return }
        await transport?.notifyLocalChanges()
    }

    /// Called only after the settings confirmation. A full pull merges content;
    /// it never chooses either side as an authoritative replacement.
    func pullFromICloud() async {
        guard isEnabled, conflict == nil, !isRunning,
            accountState == .available, let transport
        else { return }
        isRunning = true
        let generation = startGeneration
        defer {
            isRunning = false
            scheduleAccountRestartIfNeeded()
            scheduleRetryIfNeeded()
        }
        lastAttemptAt = .now
        phase = .syncing
        do {
            let count = try await transport.pullFromICloud()
            guard isCurrentStart(generation), !accountRestartRequested else { return }
            observedCloudRecordCount = count
            lastFetchedRecordCount = count
            skippedRecordCount = 0
            requiresAppUpdate = false
            recordSuccess()
        } catch {
            guard isCurrentStart(generation) else { return }
            fail(error)
        }
    }

    func resolveUsingThisDevice() async {
        guard isEnabled, conflict != nil, configuration != nil else { return }
        await resolve(usesCloud: false)
    }

    func resolveUsingICloud() async {
        guard isEnabled, conflict != nil, configuration != nil else { return }
        await resolve(usesCloud: true)
    }

    var diagnosticsReport: String {
        BrowserCloudSyncDiagnostics(
            containerIdentifier: containerIdentifier,
            isEnabled: isEnabled,
            accountState: accountState,
            phase: phase,
            localRecordCount: localRecordCount,
            pendingUploadCount: pendingUploadCount,
            observedCloudRecordCount: observedCloudRecordCount,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            lastFetchedRecordCount: lastFetchedRecordCount,
            lastUploadedRecordCount: lastUploadedRecordCount,
            hasError: errorDescription != nil || localErrorDescription != nil,
            requiresReconciliation: conflict != nil,
            skippedRecordCount: skippedRecordCount,
            requiresAppUpdate: requiresAppUpdate,
            cloudDataWasRemoved: cloudDataWasRemoved
        ).report
    }

    private func enabledStateDidChange() async {
        if isEnabled {
            if isRunning {
                accountRestartRequested = true
                return
            }
            await start()
        } else {
            startGeneration += 1
            cancelRetry()
            let previous = transport
            transport = nil
            conflict = nil
            accountRestartRequested = false
            phase = .disabled
            errorDescription = nil
            await previous?.stop()
            guard !isEnabled else { return }
            resetTransportStateUnlessAnAccountDecisionIsPending()
        }
    }

    /// Turning sync off is not an answer to "is this the same iCloud account?".
    ///
    /// Clearing the stored pause here would let the next switch on merge this
    /// device's Spaces into whichever account happens to be signed in, without
    /// ever asking again.
    private func resetTransportStateUnlessAnAccountDecisionIsPending() {
        guard (try? preferences.requiresAccountConfirmation()) != true else { return }
        try? preferences.resetTransportState()
    }

    private func prepareAccountReconciliation(
        remoteService: any BrowserCloudSyncRemoteService,
        transportFactory: any BrowserCloudSyncTransportFactory,
        generation: Int
    ) async throws {
        let remote = try await remoteService.loadSnapshot()
        guard isCurrentStart(generation) else { return }
        observedCloudRecordCount = remote.count
        // A comparison the core refuses stops here: it never reads as a device
        // with nothing to keep.
        let comparison = try await compare(with: remote)
        guard isCurrentStart(generation) else { return }
        if comparison.deviceRecords > 0, !comparison.matches {
            conflict = BrowserCloudSyncConflictSummary(comparison)
            phase = .needsReconciliation
            return
        }

        if comparison.deviceRecords == 0, comparison.cloudRecords > 0 {
            try await deliver(ReplaceWithCloudRecords(records: remote.map(SyncRecord.init(browser:))))
        }
        try preferences.resetTransportState()
        try await startTransport(
            using: transportFactory,
            generation: generation
        )
    }

    private func replaceDisposableSeedStateFromCloudIfNeeded(
        using remoteService: any BrowserCloudSyncRemoteService
    ) async throws {
        guard core.state.syncsDisposableSeed else { return }
        let remote = try await remoteService.loadSnapshot()
        observedCloudRecordCount = remote.count
        try await deliver(ReplaceSeedWithCloudRecords(records: remote.map(SyncRecord.init(browser:))))
        try preferences.resetTransportState()
    }

    /// How the stored session's journal compares with `remote`, the cloud's
    /// records, once every stage the core queued has settled. The core
    /// compares them off the main thread.
    private func compare(with remote: [BrowserSyncRecord]) async throws -> CloudContentComparison {
        let cloud = try remote.map(SyncRecord.init(browser:))
        let core = core
        return try await Task.detached(priority: .utility) {
            await core.settleSync()
            return try core.query(CloudComparison(cloud: cloud))
        }.value
    }

    /// Sends the core the person's choice, or what the first launch takes from
    /// the cloud, off the main thread. What it changed reaches the windows
    /// through the core's wake.
    private func deliver(_ intent: some CloudSyncIntent) async throws {
        let core = core
        try await Task.detached(priority: .utility) { _ = try core.deliver(intent) }.value
    }

    /// Starts CKSyncEngine and lets its system scheduler perform the routine
    /// fetch/send cycle. `syncNow()` is reserved for the explicit button so two
    /// schedulers cannot drive overlapping work at launch.
    private func startTransport(
        using transportFactory: any BrowserCloudSyncTransportFactory,
        generation: Int
    ) async throws {
        if transport == nil {
            let created = try transportFactory.makeTransport(
                statusHandler: { [weak self] status in
                    await self?.receive(status, generation: generation)
                },
                activityHandler: { [weak self] activity in
                    await self?.receive(activity, generation: generation)
                }
            )
            transport = created
            await created.start()
            guard isCurrentStart(generation) else {
                await created.stop()
                return
            }
        }
    }

    private func resolve(usesCloud: Bool) async {
        guard !isRunning, let remoteService, let transportFactory else { return }
        isRunning = true
        startGeneration += 1
        let generation = startGeneration
        defer {
            isRunning = false
            scheduleAccountRestartIfNeeded()
            scheduleRetryIfNeeded()
        }
        phase = .syncing
        lastAttemptAt = .now
        do {
            let latestRemote = try await remoteService.loadSnapshot()
            guard isCurrentStart(generation) else { return }
            observedCloudRecordCount = latestRemote.count
            let records = try latestRemote.map(SyncRecord.init(browser:))
            if usesCloud {
                try await deliver(ReplaceWithCloudRecords(records: records))
            } else {
                try await deliver(OverwriteCloud(records: records))
            }
            try preferences.saveConflictResolution(
                usesCloud ? nil : .useThisDevice
            )
            transport = nil
            conflict = nil
            try await startTransport(
                using: transportFactory,
                generation: generation
            )
        } catch {
            guard isCurrentStart(generation) else { return }
            fail(error)
        }
    }

    private func receive(_ status: BrowserCloudSyncStatus, generation: Int) {
        guard isCurrentStart(generation), conflict == nil else { return }
        switch status {
        case .stopped:
            phase = isEnabled ? .checking : .disabled
        case .syncing:
            phase = .syncing
        case .idle:
            phase = .ready
            clearRecoveredFailureIfNeeded()
        case .pausedForAccountConfirmation:
            phase = .needsReconciliation
        case .failed(let message):
            phase = .failed(message)
            errorDescription = message
        }
    }

    private func receive(_ activity: BrowserCloudSyncActivity, generation: Int) {
        guard isCurrentStart(generation) else { return }
        switch activity {
        case .fetched(let recordCount):
            lastFetchedRecordCount = recordCount
            lastSuccessAt = .now
            clearRecoveredFailureIfNeeded()
        case .uploaded(let recordCount):
            lastUploadedRecordCount = recordCount
            lastSuccessAt = .now
            clearRecoveredFailureIfNeeded()
        case .accountChanged:
            let previous = transport
            transport = nil
            startGeneration += 1
            Task { await previous?.stop() }
            conflict = nil
            accountRestartRequested = true
            phase = .checking
            scheduleAccountRestartIfNeeded()
        case .skippedRecords(let count, let needsUpdate):
            skippedRecordCount += count
            requiresAppUpdate = requiresAppUpdate || needsUpdate
        case .cloudDataRemoved:
            cloudDataWasRemoved = true
        }
    }

    private func recordSuccess() {
        if let localError = localErrorDescription {
            phase = .failed("Local changes could not be saved for sync.")
            errorDescription = localError
            return
        }
        lastSuccessAt = .now
        phase = .ready
        errorDescription = nil
        retryAttempts = 0
        cancelRetry()
    }

    /// CKSyncEngine retries transient CloudKit failures through the system
    /// scheduler. Activity arriving outside an explicit `syncNow()` proves that
    /// automatic retry recovered, so the earlier error must not remain sticky.
    private func clearRecoveredFailureIfNeeded() {
        guard !isRunning, errorDescription != nil else { return }
        phase = .ready
        errorDescription = nil
        retryAttempts = 0
        cancelRetry()
    }

    private func isCurrentStart(_ generation: Int) -> Bool {
        isEnabled && generation == startGeneration
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// Retries a launch that ended without a working transport.
    ///
    /// Nothing else would: a device that was offline or signed out when Crest
    /// launched used to stay dormant until the next launch or an explicit
    /// Sync Now.
    private func scheduleRetryIfNeeded() {
        guard isEnabled,
            conflict == nil,
            !isRunning,
            !accountRestartRequested,
            transport == nil,
            remoteService != nil,
            transportFactory != nil,
            retryTask == nil,
            retryAttempts < Self.maximumRetryAttempts,
            phase.isRetryable
        else { return }
        retryAttempts += 1
        let delay = retryDelay
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.retryAfterDelay()
        }
    }

    private func retryAfterDelay() async {
        retryTask = nil
        guard isEnabled, conflict == nil, !isRunning else { return }
        await syncNow()
    }

    /// Watches for iCloud sign-in, sign-out, and account switches.
    func observeAccountChanges(
        named name: Notification.Name,
        center: NotificationCenter = .default
    ) {
        guard accountObservation == nil else { return }
        accountObservation = center.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.accountAvailabilityDidChange()
            }
        }
    }

    /// Re-drives the start sequence against whichever account is signed in now.
    func accountAvailabilityDidChange() async {
        cancelRetry()
        retryAttempts = 0
        startGeneration += 1
        let previous = transport
        transport = nil
        conflict = nil
        accountRestartRequested = isRunning
        await previous?.stop()
        guard isEnabled else { return }
        phase = .checking
        await start()
    }

    private func scheduleAccountRestartIfNeeded() {
        guard accountRestartRequested, !isRunning else { return }
        Task { [weak self] in
            await self?.restartAfterAccountChangeIfNeeded()
        }
    }

    private func restartAfterAccountChangeIfNeeded() async {
        guard accountRestartRequested, !isRunning else { return }
        accountRestartRequested = false
        await start()
    }

    private func fail(_ error: any Error) {
        let message =
            remoteService?.message(for: error)
            ?? String(describing: error)
        errorDescription = message
        phase = .failed(message)
    }
}
