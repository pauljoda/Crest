import Foundation
import Observation
import os

/// Crest's downloads for one browsing mode: the core's download records, the
/// feedback they present, native data saves, and the transfers each engine
/// runs. Every record change is an intent sent to the core. An engine
/// either reports its own transfers (`receiveEngineDownload`) or runs them
/// through a `BrowserDownloadTransport` it registers with the center.
@Observable
@MainActor
final class BrowserDownloadCenter: NSObject {
    // MARK: - Types

    typealias CredentialPromptHandler =
        @MainActor (
            BrowserHTTPAuthenticationPrompt,
            String
        ) async -> BrowserHTTPAuthenticationPromptResponse?

    typealias CredentialLoader =
        @MainActor (
            BrowserHTTPAuthenticationProtectionSpace,
            SpaceID
        ) async throws -> BrowserCredential?

    typealias CredentialSaver =
        @MainActor (
            BrowserHTTPAuthenticationSaveRequest,
            SpaceID
        ) async throws -> Void

    /// Asks the person to approve a risky download: its assessment, source,
    /// Space name and profile.
    typealias RiskApprovalHandler =
        @MainActor (
            DownloadRiskAssessment,
            URL?,
            String,
            UUID
        ) async -> Bool

    typealias DownloadDestinationResolver =
        @MainActor (
            String,
            SpaceID,
            Bool
        ) async -> BrowserPlatformDownloadResolution

    private final class EngineTransfer {
        let itemID: UUID
        let assignment: BrowserSpaceRuntimeAssignment
        var controller: (any BrowserEngineDownloadControlling)?
        var estimator: DownloadTransferEstimator?
        var securityScopedURL: URL?
        var warningToken: String?
        var resolvingDestination = false
        var isFinished = false

        init(
            itemID: UUID, assignment: BrowserSpaceRuntimeAssignment,
            controller: any BrowserEngineDownloadControlling
        ) {
            self.itemID = itemID
            self.assignment = assignment
            self.controller = controller
        }
        func finish() {
            isFinished = true
            warningToken = nil
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
    }

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Downloads")

    /// The core whose read model holds the download records. Views observe
    /// its records directly.
    let core: CrestCore
    private(set) var feedbackEvents: [BrowserDownloadFeedbackEvent] = []

    var items: [DownloadState] {
        core.state.downloads
    }

    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let promptForCredentials: CredentialPromptHandler
    @ObservationIgnored let approveRiskyDownload: RiskApprovalHandler
    @ObservationIgnored let resolveDownloadDestination: DownloadDestinationResolver
    /// The transports engines registered, one per transport type.
    @ObservationIgnored private var transports: [ObjectIdentifier: any BrowserDownloadTransport] = [:]
    @ObservationIgnored private var feedbackExpirationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var dataSaveAssignments: [UUID: BrowserSpaceRuntimeAssignment] = [:]
    // Keep terminal identities until this center is released so a late engine
    // event cannot recreate a cleared or expired record.
    @ObservationIgnored private var engineTransfers: [BrowserEngineDownloadID: EngineTransfer] = [:]
    @ObservationIgnored private let approveEngineDownload: @MainActor (String, String) async -> Bool
    @ObservationIgnored private var lastRetentionSweepAt: Date?
    @ObservationIgnored private let loadCredential: CredentialLoader
    @ObservationIgnored private let saveCredential: CredentialSaver
    @ObservationIgnored private let allowsAnyCredentialSaving: Bool
    @ObservationIgnored private var credentialAccessBySpaceID: [SpaceID: Bool] = [:]

    // MARK: - Initializers

    init(
        core: CrestCore = CrestCore(),
        promptForCredentials: @escaping CredentialPromptHandler = { _, _ in nil },
        allowsCredentialSaving: Bool = true,
        loadCredential: @escaping CredentialLoader = { _, _ in nil },
        saveCredential: @escaping CredentialSaver = { _, _ in },
        approveRiskyDownload: @escaping RiskApprovalHandler = { _, _, _, _ in false },
        approveEngineDownload: @escaping @MainActor (String, String) async -> Bool = { _, _ in false },
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        resolveDownloadDestination:
            @escaping DownloadDestinationResolver = {
                suggestedFilename,
                spaceID,
                forcesPrompt in
                await BrowserPlatformDownloadDirectory.resolve(
                    suggestedFilename: suggestedFilename,
                    spaceID: spaceID,
                    forcesPrompt: forcesPrompt
                )
            }
    ) {
        self.core = core
        self.promptForCredentials = promptForCredentials
        allowsAnyCredentialSaving = allowsCredentialSaving
        self.loadCredential = loadCredential
        self.saveCredential = saveCredential
        self.approveRiskyDownload = approveRiskyDownload
        self.approveEngineDownload = approveEngineDownload
        self.permissionCenter = permissionCenter
        self.resolveDownloadDestination = resolveDownloadDestination
        super.init()
    }

    // MARK: - Actions - Transports

    /// The center's transport of `Transport`'s type, made on first use.
    func transport<Transport: BrowserDownloadTransport>(
        _ make: (BrowserDownloadCenter) -> Transport
    ) -> Transport {
        let key = ObjectIdentifier(Transport.self)
        if let existing = transports[key] as? Transport { return existing }
        let transport = make(self)
        transports[key] = transport
        return transport
    }

    /// Starts a new automatic-download sequence for the page `engine` hosts,
    /// once its document is replaced or the page goes away.
    func resetAutomaticDownloadSequence(for engine: any BrowserPageEngine) {
        let pageView = ObjectIdentifier(engine.nativeView)
        for transport in transports.values {
            transport.resetAutomaticDownloadSequence(forPageView: pageView)
        }
    }

    // MARK: - Actions - Credentials

    func setCredentialAccessEnabled(_ isEnabled: Bool, in spaceID: SpaceID) {
        credentialAccessBySpaceID[spaceID] = isEnabled
        for transport in transports.values {
            transport.setCredentialStorageEnabled(allowsAnyCredentialSaving && isEnabled, in: spaceID)
        }
    }

    func isCredentialAccessEnabled(in spaceID: SpaceID) -> Bool {
        allowsAnyCredentialSaving && (credentialAccessBySpaceID[spaceID] ?? true)
    }

    /// The HTTP authentication session for one transfer in `spaceID`, saving
    /// credentials only where the Space allows it.
    func makeAuthenticationSession(in spaceID: SpaceID) -> BrowserHTTPAuthenticationSession {
        BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: isCredentialAccessEnabled(in: spaceID),
            loadCredential: { [loadCredential] protectionSpace in
                try await loadCredential(protectionSpace, spaceID)
            },
            saveCredential: { [saveCredential] request in
                try await saveCredential(request, spaceID)
            }
        )
    }

    // MARK: - Actions - Records

    func items(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID && !$0.isAcknowledged }
    }

    func item(_ itemID: UUID) -> DownloadState? {
        items.first { $0.id == itemID }
    }

    /// Sends one download intent. A refused intent changes nothing; the rule
    /// it broke is logged, since it means an engine reported something the
    /// core cannot record.
    func send(_ intent: some Intent) {
        do {
            try core.send(intent)
        } catch {
            Self.logger.error(
                "The core refused \(String(describing: type(of: intent)), privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Begins a new record and returns its identity.
    func begin(profileID: UUID, filename: String, createdAt: Date = .now, isAcknowledged: Bool = false) -> UUID {
        let itemID = UUID()
        send(
            BeginDownload(
                downloadID: itemID, profileID: profileID, filename: filename, createdAt: createdAt,
                isAcknowledged: isAcknowledged))
        return itemID
    }

    /// The destination names the file, so the record's filename follows it.
    func setDestination(_ destination: URL, for itemID: UUID) {
        send(
            SetDownloadDestination(
                downloadID: itemID, destination: destination.absoluteString, filename: destination.lastPathComponent))
    }

    /// One progress reading for a transfer. `estimator` is the state the
    /// caller keeps for that transfer; the reading replaces it. Nil when the
    /// core refuses the sample, and the caller keeps its last reading.
    func sampleProgress(
        _ estimator: inout DownloadTransferEstimator?,
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        fractionCompleted: Double,
        isPaused: Bool,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DownloadProgressReading? {
        let sample = DownloadProgress(
            estimator: estimator, completedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted.isFinite ? fractionCompleted : 0, isPaused: isPaused, uptime: uptime)
        guard let reading = try? core.query(sample) else { return nil }
        estimator = reading.estimator
        return reading
    }

    /// The core's risk verdict for a download. A download the core cannot
    /// judge asks the person first rather than passing as safe.
    func riskVerdict(suggestedFilename: String, mimeType: String?, isUserInitiated: Bool) -> DownloadRiskVerdict {
        let facts = DownloadRiskFacts(suggestedFilename: suggestedFilename, mimeType: mimeType)
        do {
            return try core.query(DownloadRisk(facts: facts, isUserInitiated: isUserInitiated))
        } catch {
            return DownloadRiskVerdict(
                assessment: DownloadRiskAssessment(sanitizedFilename: facts.sanitizedFilename, reasons: []),
                requiresConfirmation: true)
        }
    }

    @discardableResult
    func acknowledgeItems(for profileID: UUID) -> Int {
        (try? core.send(AcknowledgeDownloads(profileID: profileID)))?.count ?? 0
    }

    /// Removes only Crest's terminal download records. Files already written to
    /// their destination remain untouched.
    @discardableResult
    func sweepExpiredRecords(
        using session: BrowserSession,
        now: Date = .now,
        force: Bool = false
    ) -> Bool {
        guard
            force
                || BrowserCurrentTabCleanupSchedule.allowsSweep(
                    lastSweptAt: lastRetentionSweepAt,
                    now: now
                )
        else {
            return false
        }
        lastRetentionSweepAt = now
        let expiry = ExpireDownloads(
            now: now,
            retentions: session.spaces.map {
                DownloadRetention(
                    profileID: $0.profile.id, lifetime: $0.browsingPreferences.dataRetention.downloads.lifetime)
            })
        let changes = (try? core.send(expiry)) ?? []
        for case .downloadsRemoved(let removal) in changes {
            for itemID in removal.downloadIDs {
                forgetEngineDownload(itemID)
                for transport in transports.values { transport.forget(itemID) }
            }
        }
        return true
    }

    func cancel(_ itemID: UUID) {
        if let (id, transfer) = engineTransfers.first(where: { $0.value.itemID == itemID && !$0.value.isFinished }) {
            let controller = transfer.controller
            transfer.finish()
            send(CancelDownload(downloadID: itemID, message: "Canceled."))
            controller?.cancelDownload(id)
            return
        }
        if dataSaveAssignments.removeValue(forKey: itemID) != nil {
            send(CancelDownload(downloadID: itemID, message: "Canceled."))
            return
        }
        for transport in transports.values where transport.cancel(itemID) { return }
    }

    func clear(_ itemID: UUID) {
        guard !engineTransfers.values.contains(where: { $0.itemID == itemID && !$0.isFinished }) else { return }
        guard !transports.values.contains(where: { $0.isTransferring(itemID) }),
            dataSaveAssignments[itemID] == nil
        else { return }
        forgetEngineDownload(itemID)
        send(RemoveDownload(downloadID: itemID))
        for transport in transports.values { transport.forget(itemID) }
    }

    func deleteRecords(profileID: UUID, spaceID: SpaceID) {
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        for transfer in engineTransfers.values where transfer.assignment == assignment {
            cancel(transfer.itemID)
            forgetEngineDownload(transfer.itemID)
        }
        dataSaveAssignments = dataSaveAssignments.filter { $0.value != assignment }
        for transport in transports.values { transport.removeTransfers(in: assignment) }
        send(RemoveProfileDownloads(profileID: profileID))
    }

    @discardableResult
    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable:
            @escaping @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) async -> Bool {
        guard let item = item(itemID),
            item.profileID == assignment.profileID,
            item.phase == .blockedAutomaticDownload
        else {
            return false
        }
        for transport in Array(transports.values) {
            if let retried = await transport.retryAutomaticDownload(
                itemID, matching: assignment, isAssignmentAvailable: isAssignmentAvailable)
            {
                return retried
            }
        }
        send(FailDownload(downloadID: itemID, message: "Reload the original page, then try the download again."))
        return false
    }

    // MARK: - Actions - Engine-reported transfers

    func receiveEngineDownload(
        _ update: BrowserEngineDownloadUpdate,
        assignment: BrowserSpaceRuntimeAssignment,
        controller: any BrowserEngineDownloadControlling
    ) {
        guard update.id.profileID == assignment.profileID else { return }
        let transfer: EngineTransfer
        if let existing = engineTransfers[update.id] {
            guard existing.assignment == assignment, !existing.isFinished else { return }
            transfer = existing
        } else {
            transfer = EngineTransfer(
                itemID: begin(
                    profileID: assignment.profileID,
                    filename: BrowserDownloadDestination.safeFilename(from: update.filename),
                    createdAt: update.createdAt,
                    isAcknowledged: update.isRestored),
                assignment: assignment, controller: controller)
            engineTransfers[update.id] = transfer
        }
        if let destination = update.destination {
            setDestination(destination, for: transfer.itemID)
        }
        if let reading = sampleProgress(
            &transfer.estimator, completedUnitCount: update.bytesReceived, totalUnitCount: update.totalBytes,
            fractionCompleted: update.totalBytes > 0 ? Double(update.bytesReceived) / Double(update.totalBytes) : 0,
            isPaused: update.isPaused)
        {
            send(
                RecordDownloadTransfer(
                    downloadID: transfer.itemID, telemetry: reading.telemetry, progress: reading.progress))
        }
        switch update.state {
        case .preparing, .downloading:
            transfer.warningToken = nil
        case .finished:
            send(FinishDownload(downloadID: transfer.itemID, finalByteCount: update.bytesReceived))
            transfer.finish()
        case .canceled:
            send(CancelDownload(downloadID: transfer.itemID, message: "Canceled."))
            transfer.finish()
        case .failed(let message):
            send(FailDownload(downloadID: transfer.itemID, message: message))
            transfer.finish()
        case .awaitingApproval(let token, let message):
            send(AwaitDownloadApproval(downloadID: transfer.itemID))
            guard transfer.warningToken != token else { return }
            transfer.warningToken = token
            Task { [weak self, weak transfer] in
                guard let self, let transfer else { return }
                let approved = await approveEngineDownload(update.filename, message)
                guard !transfer.isFinished, transfer.warningToken == token else { return }
                if approved {
                    transfer.controller?.approveDownload(update.id, warningToken: token)
                } else {
                    cancel(transfer.itemID)
                }
            }
        }
    }

    private func forgetEngineDownload(_ itemID: UUID) {
        guard let (id, transfer) = engineTransfers.first(where: { $0.value.itemID == itemID }),
            transfer.isFinished
        else { return }
        transfer.controller?.removeDownload(id)
        transfer.controller = nil
    }

    func resolveEngineDownloadDestination(
        _ id: BrowserEngineDownloadID, suggestedFilename: String, forcesPrompt: Bool
    ) async -> URL? {
        guard let transfer = engineTransfers[id], !transfer.isFinished,
            !transfer.resolvingDestination
        else { return nil }
        transfer.resolvingDestination = true
        defer { transfer.resolvingDestination = false }
        let resolution = await resolveDownloadDestination(
            BrowserDownloadDestination.safeFilename(from: suggestedFilename), transfer.assignment.spaceID, forcesPrompt)
        guard !transfer.isFinished else {
            if case .destination(_, let scoped) = resolution { scoped?.stopAccessingSecurityScopedResource() }
            return nil
        }
        switch resolution {
        case .destination(let url, let scoped):
            transfer.securityScopedURL?.stopAccessingSecurityScopedResource()
            transfer.securityScopedURL = scoped
            setDestination(url, for: transfer.itemID)
            return url
        case .cancelled:
            cancel(transfer.itemID)
        case .unavailable:
            let controller = transfer.controller
            send(
                FailDownload(
                    downloadID: transfer.itemID,
                    message: "The download folder is unavailable. Choose another folder in Space settings."))
            transfer.finish()
            controller?.cancelDownload(id)
        }
        return nil
    }

    // MARK: - Actions - Native data saves

    /// Saves bytes supplied by a trusted native user action, such as WebKit's
    /// PDF toolbar. No network request or automatic-download permission is
    /// involved, but destination consent and file safeguards still apply.
    @discardableResult
    func saveData(
        _ data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String,
        feedbackSource: BrowserDownloadFeedbackSource? = nil
    ) async -> UUID {
        let verdict = riskVerdict(suggestedFilename: suggestedFilename, mimeType: mimeType, isUserInitiated: true)
        let assessment = verdict.assessment
        let itemID = begin(profileID: assignment.profileID, filename: assessment.sanitizedFilename)
        send(AssessDownloadRisk(downloadID: itemID, assessment: assessment))
        dataSaveAssignments[itemID] = assignment
        if let feedbackSource {
            presentFeedback(
                BrowserDownloadFeedbackEvent(
                    id: itemID, profileID: assignment.profileID, spaceID: assignment.spaceID,
                    filename: assessment.sanitizedFilename, source: feedbackSource))
        }
        await finishSavingData(
            data, itemID: itemID, verdict: verdict, originatingURL: originatingURL,
            assignment: assignment, spaceName: spaceName)
        return itemID
    }

    private func finishSavingData(
        _ data: Data,
        itemID: UUID,
        verdict: DownloadRiskVerdict,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String
    ) async {
        defer { dataSaveAssignments.removeValue(forKey: itemID) }
        guard dataSaveAssignments[itemID] == assignment else { return }
        let assessment = verdict.assessment
        if verdict.requiresConfirmation {
            let approved = await approveRiskyDownload(assessment, originatingURL, spaceName, assignment.profileID)
            guard dataSaveAssignments[itemID] == assignment else { return }
            guard approved else {
                send(
                    CancelDownload(
                        downloadID: itemID, message: "Canceled before downloading a potentially dangerous file."))
                return
            }
        }
        let resolution = await resolveDownloadDestination(assessment.sanitizedFilename, assignment.spaceID, false)
        // Cancellation or removal of the owning Space can happen while a
        // native panel is open. A late response must never resurrect the save.
        guard dataSaveAssignments[itemID] == assignment else { return }
        switch resolution {
        case .cancelled:
            send(CancelDownload(downloadID: itemID, message: "Canceled."))
        case .unavailable:
            #if os(macOS)
                send(
                    FailDownload(
                        downloadID: itemID,
                        message:
                            "The download folder is unavailable. Open Crest Settings > General > System Permissions to check folder access or choose another folder."
                    ))
            #else
                send(FailDownload(downloadID: itemID, message: "The Downloads folder is unavailable."))
            #endif
        case .destination(let destination, let resourceURL):
            let scoped = resourceURL?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { resourceURL?.stopAccessingSecurityScopedResource() } }
            do {
                try saveDataToDestination(
                    data, itemID: itemID, destination: destination, originatingURL: originatingURL)
                send(FinishDownload(downloadID: itemID, finalByteCount: Int64(data.count)))
            } catch {
                send(FailDownload(downloadID: itemID, message: error.localizedDescription))
            }
        }
    }

    private func saveDataToDestination(
        _ data: Data, itemID: UUID, destination: URL, originatingURL: URL
    ) throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let stagingDirectory =
            applicationSupport
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("Download Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = BrowserDownloadTransfer.stagingURL(
            itemID: itemID, suggestedFilename: destination.lastPathComponent, directory: stagingDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        setDestination(destination, for: itemID)
        try data.write(to: staging, options: .atomic)
        try BrowserDownloadTransfer.finish(
            from: staging, to: destination, quarantine: BrowserDownloadQuarantine(sourceURL: originatingURL))
    }

    // MARK: - Actions - Feedback

    func dismissFeedback(_ eventID: UUID) {
        feedbackEvents.removeAll { $0.id == eventID }
        feedbackExpirationTasks.removeValue(forKey: eventID)?.cancel()
    }

    func presentFeedback(_ event: BrowserDownloadFeedbackEvent) {
        let previousIDs = Set(feedbackEvents.map(\.id))
        feedbackEvents = BrowserDownloadFeedbackPolicy.bounded(
            feedbackEvents,
            appending: event
        )
        let retainedIDs = Set(feedbackEvents.map(\.id))
        for removedID in previousIDs.subtracting(retainedIDs) {
            feedbackExpirationTasks.removeValue(forKey: removedID)?.cancel()
        }
        feedbackExpirationTasks[event.id]?.cancel()
        feedbackExpirationTasks[event.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserDownloadFeedbackPolicy.lifetime)
            guard !Task.isCancelled else { return }
            self?.dismissFeedback(event.id)
        }
    }
}
