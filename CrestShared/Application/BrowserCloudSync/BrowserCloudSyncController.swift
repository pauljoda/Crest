import Foundation
import Observation

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

    @ObservationIgnored private let workflow: any BrowserCloudSyncWorkflowGateway
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

    init(
        workflow: any BrowserCloudSyncWorkflowGateway,
        configuration: BrowserCloudSyncConfiguration?,
        preferences: any BrowserCloudSyncPreferences,
        remoteService: (any BrowserCloudSyncRemoteService)?,
        transportFactory: (any BrowserCloudSyncTransportFactory)?,
        retryDelay: Duration = .seconds(30)
    ) {
        self.workflow = workflow
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
            localRecordCount: workflow.cloudSyncLocalRecordCount,
            pendingUploadCount: workflow.cloudSyncPendingRecordCount,
            observedCloudRecordCount: observedCloudRecordCount,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            lastFetchedRecordCount: lastFetchedRecordCount,
            lastUploadedRecordCount: lastUploadedRecordCount,
            hasError: errorDescription != nil
                || workflow.cloudSyncLocalErrorDescription != nil,
            requiresReconciliation: conflict != nil,
            skippedRecordCount: skippedRecordCount,
            requiresAppUpdate: requiresAppUpdate,
            cloudDataWasRemoved: cloudDataWasRemoved
        ).report
    }

    private func enabledStateDidChange() async {
        if isEnabled {
            await start()
        } else {
            startGeneration += 1
            cancelRetry()
            transport = nil
            conflict = nil
            accountRestartRequested = false
            phase = .disabled
            errorDescription = nil
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
        let local = await workflow.cloudSyncRecords()
        guard isCurrentStart(generation) else { return }
        if !local.isEmpty,
            !BrowserSyncContentComparison.hasEquivalentContent(
                localRecords: local,
                remoteRecords: remote
            )
        {
            conflict = BrowserCloudSyncConflictSummary.comparing(
                localRecords: local,
                cloudRecords: remote
            )
            phase = .needsReconciliation
            return
        }

        if local.isEmpty, !remote.isEmpty {
            try workflow.replaceLocalWithCloud(remote)
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
        guard workflow.hasDisposableCloudSyncSeed else { return }
        let remote = try await remoteService.loadSnapshot()
        observedCloudRecordCount = remote.count
        try workflow.replaceDisposableSeedWithCloud(remote)
        try preferences.resetTransportState()
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
                    await self?.receive(status)
                },
                activityHandler: { [weak self] activity in
                    await self?.receive(activity)
                }
            )
            transport = created
            await created.start()
            guard isCurrentStart(generation) else {
                transport = nil
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
            if usesCloud {
                try workflow.replaceLocalWithCloud(latestRemote)
            } else {
                try workflow.prepareToOverwriteCloud(with: latestRemote)
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

    private func receive(_ status: BrowserCloudSyncStatus) {
        guard conflict == nil else { return }
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

    private func receive(_ activity: BrowserCloudSyncActivity) {
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
            transport = nil
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
        transport = nil
        conflict = nil
        accountRestartRequested = false
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
