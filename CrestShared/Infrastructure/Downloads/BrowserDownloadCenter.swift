import Combine
import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class BrowserDownloadCenter: NSObject {
    private struct AutomaticDownloadScope: Hashable {
        let webViewID: ObjectIdentifier
        let origin: BrowserSiteOrigin
        let spaceID: SpaceID
    }

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

    typealias RiskApprovalHandler =
        @MainActor (
            BrowserDownloadRiskAssessment,
            URL?,
            String
        ) async -> Bool

    typealias AutomaticDownloadApprovalHandler =
        @MainActor (
            String,
            BrowserSiteOrigin,
            String
        ) async -> BrowserSitePermissionPromptResponse

    private(set) var ledger = BrowserDownloadLedger()

    @ObservationIgnored private var downloads: [ObjectIdentifier: WKDownload] = [:]
    @ObservationIgnored private var itemIDs: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var progressObservations: [ObjectIdentifier: AnyCancellable] = [:]
    @ObservationIgnored private var stagingURLs: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var destinationURLs: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var securityScopedResources: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var spaceNames: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var spaceIDs: [ObjectIdentifier: SpaceID] = [:]
    @ObservationIgnored private var sourceOrigins: [ObjectIdentifier: BrowserSiteOrigin] = [:]
    @ObservationIgnored private var sourceWebViewIDs: [ObjectIdentifier: ObjectIdentifier] = [:]
    @ObservationIgnored private var automaticDownloadSequences:
        [AutomaticDownloadScope: BrowserAutomaticDownloadSequence] = [:]
    @ObservationIgnored private var approvedRetryKeys: Set<ObjectIdentifier> = []
    @ObservationIgnored private var userInitiatedOverrideKeys: Set<ObjectIdentifier> = []
    @ObservationIgnored private var retryContexts: [UUID: BrowserDownloadRetryContext] = [:]
    @ObservationIgnored private var retryLeases: [UUID: BrowserDownloadRetryLease] = [:]
    @ObservationIgnored private var authenticationSessions: [ObjectIdentifier: BrowserHTTPAuthenticationSession] = [:]
    @ObservationIgnored private var lastRetentionSweepAt: Date?
    @ObservationIgnored private let promptForCredentials: CredentialPromptHandler
    @ObservationIgnored private let loadCredential: CredentialLoader
    @ObservationIgnored private let saveCredential: CredentialSaver
    @ObservationIgnored private let allowsAnyCredentialSaving: Bool
    @ObservationIgnored private var credentialAccessBySpaceID: [SpaceID: Bool] = [:]
    @ObservationIgnored private let approveRiskyDownload: RiskApprovalHandler
    @ObservationIgnored private let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored private let approveAutomaticDownload: AutomaticDownloadApprovalHandler

    init(
        ledger: BrowserDownloadLedger = BrowserDownloadLedger(),
        promptForCredentials: @escaping CredentialPromptHandler = { _, _ in nil },
        allowsCredentialSaving: Bool = true,
        loadCredential: @escaping CredentialLoader = { _, _ in nil },
        saveCredential: @escaping CredentialSaver = { _, _ in },
        approveRiskyDownload: @escaping RiskApprovalHandler = { _, _, _ in false },
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        approveAutomaticDownload:
            @escaping AutomaticDownloadApprovalHandler = { _, _, _ in .denyPersistently }
    ) {
        self.ledger = ledger
        self.promptForCredentials = promptForCredentials
        allowsAnyCredentialSaving = allowsCredentialSaving
        self.loadCredential = loadCredential
        self.saveCredential = saveCredential
        self.approveRiskyDownload = approveRiskyDownload
        self.permissionCenter = permissionCenter
        self.approveAutomaticDownload = approveAutomaticDownload
        super.init()
    }

    var items: [BrowserDownloadItem] {
        ledger.items
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool, in spaceID: SpaceID) {
        credentialAccessBySpaceID[spaceID] = isEnabled
        for (key, session) in authenticationSessions where spaceIDs[key] == spaceID {
            session.setCredentialStorageEnabled(
                allowsAnyCredentialSaving && isEnabled
            )
        }
    }

    func isCredentialAccessEnabled(in spaceID: SpaceID) -> Bool {
        allowsAnyCredentialSaving && (credentialAccessBySpaceID[spaceID] ?? true)
    }

    func items(for profileID: UUID) -> [BrowserDownloadItem] {
        ledger.items(for: profileID)
    }

    func unacknowledgedItems(for profileID: UUID) -> [BrowserDownloadItem] {
        ledger.unacknowledgedItems(for: profileID)
    }

    func acknowledgeItems(for profileID: UUID) {
        ledger.acknowledgeItems(for: profileID)
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
        let retentionByProfileID = session.spaces.reduce(
            into: [UUID: BrowserDataRetentionDuration]()
        ) { policies, space in
            let proposed = space.browsingPreferences.dataRetention.downloads
            guard let existing = policies[space.profile.id] else {
                policies[space.profile.id] = proposed
                return
            }
            policies[space.profile.id] = Self.shorter(existing, proposed)
        }
        let removedItemIDs = ledger.removeExpiredRecords(
            retentionByProfileID: retentionByProfileID,
            now: now
        )
        for itemID in removedItemIDs {
            retryContexts.removeValue(forKey: itemID)
            retryLeases.removeValue(forKey: itemID)
        }
        return true
    }

    func cancel(_ itemID: UUID) {
        if retryLeases.removeValue(forKey: itemID) != nil {
            ledger.cancel(itemID, message: "Canceled.")
            return
        }
        guard let entry = itemIDs.first(where: { $0.value == itemID }),
            let download = downloads[entry.key]
        else { return }
        download.cancel { _ in }
        removeStagingFile(for: entry.key)
        ledger.cancel(itemID, message: "Canceled.")
        release(download)
    }

    func clear(_ itemID: UUID) {
        guard !itemIDs.values.contains(itemID) else { return }
        ledger.remove(itemID)
        retryContexts.removeValue(forKey: itemID)
        retryLeases.removeValue(forKey: itemID)
    }

    func deleteRecords(profileID: UUID, spaceID: SpaceID) {
        let activeKeys = spaceIDs.compactMap { key, owningSpaceID in
            owningSpaceID == spaceID ? key : nil
        }
        for key in activeKeys {
            guard let download = downloads[key] else { continue }
            download.cancel { _ in }
            removeStagingFile(for: key)
            release(download)
        }
        ledger.removeAll(for: profileID)
        retryContexts = retryContexts.filter { _, context in
            context.assignment.profileID != profileID
                || context.assignment.spaceID != spaceID
        }
        retryLeases = retryLeases.filter { _, lease in
            lease.assignment.profileID != profileID
                || lease.assignment.spaceID != spaceID
        }
        automaticDownloadSequences = automaticDownloadSequences.filter {
            $0.key.spaceID != spaceID
        }
    }

    func resetAutomaticDownloadSequence(in webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        automaticDownloadSequences = automaticDownloadSequences.filter {
            $0.key.webViewID != webViewID
        }
    }

    private static func shorter(
        _ lhs: BrowserDataRetentionDuration,
        _ rhs: BrowserDataRetentionDuration
    ) -> BrowserDataRetentionDuration {
        switch (lhs.lifetime, rhs.lifetime) {
        case (nil, nil): lhs
        case (nil, _): rhs
        case (_, nil): lhs
        case (let lhsLifetime?, let rhsLifetime?):
            lhsLifetime <= rhsLifetime ? lhs : rhs
        }
    }

    func start(
        _ download: WKDownload,
        in webView: WKWebView,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String,
        isUserInitiated: Bool? = nil
    ) {
        let requestedFilename = download.originalRequest?.url?.lastPathComponent
        let filename = requestedFilename.flatMap { $0.isEmpty ? nil : $0 } ?? "download"
        let itemID = ledger.begin(profileID: profileID, filename: filename)
        if let request = download.originalRequest {
            retryContexts[itemID] = BrowserDownloadRetryContext(
                webView: webView,
                request: request,
                profileID: profileID,
                spaceID: spaceID,
                spaceName: spaceName
            )
        }
        register(
            download,
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID,
            spaceName: spaceName,
            sourceWebView: webView,
            isUserApprovedRetry: false,
            isUserInitiatedOverride: isUserInitiated
        )
    }

    @discardableResult
    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable: @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) async -> Bool {
        guard let item = ledger.items.first(where: { $0.id == itemID }),
            item.profileID == assignment.profileID,
            item.state == .blockedAutomaticDownload
        else {
            return false
        }
        guard let context = retryContexts[itemID],
            context.assignment == assignment,
            let webView = context.webView
        else {
            ledger.fail(
                itemID,
                message: "Reload the original page, then try the download again."
            )
            return false
        }
        guard isAssignmentAvailable(assignment) else { return false }
        let lease = BrowserDownloadRetryLease(
            id: UUID(),
            itemID: itemID,
            profileID: context.assignment.profileID,
            spaceID: context.assignment.spaceID
        )
        retryLeases[itemID] = lease
        ledger.restart(itemID)
        let download = await webView.startDownload(using: context.request)
        if Task.isCancelled {
            rejectRetryRegistration(download, itemID: itemID, lease: lease)
            return false
        }
        let currentItem = ledger.items.first { $0.id == itemID }
        let currentContext = retryContexts[itemID]
        guard
            BrowserDownloadRetryRegistrationPolicy.shouldRegister(
                lease: lease,
                currentLease: retryLeases[itemID],
                item: currentItem,
                contextAssignment: currentContext === context
                    ? currentContext?.assignment
                    : nil,
                isAssignmentAvailable: isAssignmentAvailable(assignment)
            )
        else {
            rejectRetryRegistration(download, itemID: itemID, lease: lease)
            return false
        }
        retryLeases.removeValue(forKey: itemID)
        register(
            download,
            itemID: itemID,
            profileID: context.assignment.profileID,
            spaceID: context.assignment.spaceID,
            spaceName: context.spaceName,
            sourceWebView: webView,
            isUserApprovedRetry: true,
            isUserInitiatedOverride: nil
        )
        return true
    }

    private func rejectRetryRegistration(
        _ download: WKDownload,
        itemID: UUID,
        lease: BrowserDownloadRetryLease
    ) {
        if retryLeases[itemID] == lease {
            retryLeases.removeValue(forKey: itemID)
            if ledger.items.first(where: { $0.id == itemID })?.state == .preparing {
                ledger.blockAutomaticDownload(itemID)
            }
        }
        download.cancel { _ in }
    }

    private func register(
        _ download: WKDownload,
        itemID: UUID,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String,
        sourceWebView: WKWebView,
        isUserApprovedRetry: Bool,
        isUserInitiatedOverride: Bool?
    ) {
        let key = ObjectIdentifier(download)
        guard downloads[key] == nil else { return }

        downloads[key] = download
        itemIDs[key] = itemID
        if isUserApprovedRetry {
            approvedRetryKeys.insert(key)
        }
        if isUserInitiatedOverride == true {
            userInitiatedOverrideKeys.insert(key)
        }
        spaceNames[key] = spaceName
        spaceIDs[key] = spaceID
        sourceWebViewIDs[key] = ObjectIdentifier(sourceWebView)
        let frameOrigin = BrowserSiteOrigin(download.originatingFrame.securityOrigin)
        if !frameOrigin.host.isEmpty {
            sourceOrigins[key] = frameOrigin
        } else if let sourceURL = download.originalRequest?.url,
            let sourceOrigin = BrowserSiteOrigin(url: sourceURL)
        {
            sourceOrigins[key] = sourceOrigin
        }
        authenticationSessions[key] = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: isCredentialAccessEnabled(in: spaceID),
            loadCredential: { [loadCredential] protectionSpace in
                try await loadCredential(protectionSpace, spaceID)
            },
            saveCredential: { [saveCredential] request in
                try await saveCredential(request, spaceID)
            }
        )
        download.delegate = self
        progressObservations[key] = download.progress.publisher(for: \.fractionCompleted)
            .receive(on: DispatchQueue.main)
            .map(BrowserDownloadProgressPolicy.normalized)
            .removeDuplicates { previous, next in
                !BrowserDownloadProgressPolicy.shouldPublish(
                    previous: previous,
                    next: next
                )
            }
            .sink { [weak self] progress in
                MainActor.assumeIsolated {
                    self?.ledger.setProgress(progress, for: itemID)
                }
            }
    }

    func destinationURL(
        for download: WKDownload,
        response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let fileManager = FileManager.default
        guard
            let applicationSupportDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first,
            let itemID = itemIDs[ObjectIdentifier(download)]
        else {
            fail(download, message: "The Downloads folder is unavailable.")
            release(download)
            return nil
        }

        let key = ObjectIdentifier(download)
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: suggestedFilename,
            mimeType: response.mimeType
        )
        update(download) { ledger, itemID in
            ledger.setRiskAssessment(assessment, for: itemID)
        }
        let savedDecision: BrowserSitePermissionDecision
        if let origin = sourceOrigins[key], let spaceID = spaceIDs[key] {
            savedDecision = permissionCenter.decision(
                for: .automaticDownloads,
                origin: origin,
                in: spaceID
            )
        } else {
            savedDecision = .denyPersistently
        }
        let automaticDownloadAction: BrowserAutomaticDownloadAction
        let isUserInitiated = download.isUserInitiated
            || userInitiatedOverrideKeys.contains(key)
        if let origin = sourceOrigins[key],
            let webViewID = sourceWebViewIDs[key],
            let spaceID = spaceIDs[key]
        {
            let scope = AutomaticDownloadScope(
                webViewID: webViewID,
                origin: origin,
                spaceID: spaceID
            )
            var sequence =
                automaticDownloadSequences[scope]
                ?? BrowserAutomaticDownloadSequence()
            automaticDownloadAction = sequence.action(
                isUserInitiated: isUserInitiated,
                savedDecision: savedDecision,
                isUserApprovedRetry: approvedRetryKeys.contains(key)
            )
            automaticDownloadSequences[scope] = sequence
        } else {
            automaticDownloadAction = BrowserAutomaticDownloadPolicy.action(
                isUserInitiated: isUserInitiated,
                savedDecision: savedDecision,
                isUserApprovedRetry: approvedRetryKeys.contains(key)
            )
        }
        switch automaticDownloadAction {
        case .allow:
            break
        case .deny:
            update(download) { ledger, itemID in
                ledger.blockAutomaticDownload(itemID)
            }
            release(download)
            return nil
        case .requestPermission:
            guard
                await approveAutomaticDownloadIfNeeded(
                    download,
                    filename: assessment.sanitizedFilename
                )
            else {
                update(download) { ledger, itemID in
                    ledger.blockAutomaticDownload(itemID)
                }
                release(download)
                return nil
            }
        }
        if assessment.requiresConfirmation(
            isUserInitiated: isUserInitiated
        ) {
            let approved = await approveRiskyDownload(
                assessment,
                response.url ?? download.originalRequest?.url,
                spaceNames[key] ?? "this"
            )
            guard approved else {
                update(download) { ledger, itemID in
                    ledger.cancel(itemID, message: "Canceled before downloading a potentially dangerous file.")
                }
                release(download)
                return nil
            }
        }

        guard let spaceID = spaceIDs[key] else {
            fail(download, message: "The download no longer belongs to a Space.")
            release(download)
            return nil
        }
        let resolution = await BrowserPlatformDownloadDirectory.resolve(
            suggestedFilename: assessment.sanitizedFilename,
            spaceID: spaceID,
            fileManager: fileManager
        )
        let destination: URL
        let securityScopedURL: URL?
        switch resolution {
        case .destination(let url, let resourceURL):
            destination = url
            securityScopedURL = resourceURL
        case .cancelled:
            update(download) { ledger, itemID in
                ledger.cancel(itemID, message: "Canceled.")
            }
            release(download)
            return nil
        case .unavailable:
            fail(download, message: "The Downloads folder is unavailable.")
            release(download)
            return nil
        }
        if let securityScopedURL,
            securityScopedURL.startAccessingSecurityScopedResource()
        {
            securityScopedResources[key] = securityScopedURL
        }
        let downloadsDirectory = destination.deletingLastPathComponent()
        let stagingDirectory =
            applicationSupportDirectory
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("Download Staging", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            fail(download, message: error.localizedDescription)
            release(download)
            return nil
        }

        let staging = BrowserDownloadTransfer.stagingURL(
            itemID: itemID,
            suggestedFilename: suggestedFilename,
            directory: stagingDirectory
        )
        stagingURLs[key] = staging
        destinationURLs[key] = destination
        update(download) { ledger, itemID in
            ledger.setDestination(destination, for: itemID)
        }
        return staging
    }

    func finish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        var authenticationSucceeded = false
        defer {
            release(download, authenticationSucceeded: authenticationSucceeded)
        }

        guard let staging = stagingURLs[key], let destination = destinationURLs[key] else {
            fail(download, message: "The completed download has no destination.")
            return
        }

        do {
            let quarantine = BrowserDownloadQuarantine(sourceURL: download.originalRequest?.url)
            try BrowserDownloadTransfer.finish(
                from: staging,
                to: destination,
                quarantine: quarantine
            )
            update(download) { ledger, itemID in
                ledger.finish(itemID)
            }
            authenticationSucceeded = true
        } catch {
            fail(download, message: error.localizedDescription)
        }
    }

    func handleFailure(
        for download: WKDownload,
        error: any Error,
        resumeData: Data?
    ) {
        fail(download, message: error.localizedDescription)
        release(download)
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for download: WKDownload,
        completionHandler:
            @escaping @MainActor @Sendable (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
    ) {
        let key = ObjectIdentifier(download)
        guard let authenticationSession = authenticationSessions[key] else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let spaceName = spaceNames[key] ?? "this"
        Task {
            let resolution = await authenticationSession.response(
                to: challenge
            ) { [promptForCredentials, spaceName] prompt in
                await promptForCredentials(prompt, spaceName)
            }
            completionHandler(resolution.disposition, resolution.credential)
        }
    }

    private func fail(_ download: WKDownload, message: String) {
        removeStagingFile(for: ObjectIdentifier(download))
        update(download) { ledger, itemID in
            ledger.fail(itemID, message: message)
        }
    }

    private func removeStagingFile(for key: ObjectIdentifier) {
        guard let stagingURL = stagingURLs[key] else { return }
        try? FileManager.default.removeItem(at: stagingURL)
    }

    private func update(
        _ download: WKDownload,
        mutation: (inout BrowserDownloadLedger, UUID) -> Void
    ) {
        let key = ObjectIdentifier(download)
        guard let itemID = itemIDs[key] else { return }
        mutation(&ledger, itemID)
    }

    private func approveAutomaticDownloadIfNeeded(
        _ download: WKDownload,
        filename: String
    ) async -> Bool {
        let key = ObjectIdentifier(download)
        guard let spaceID = spaceIDs[key],
            let origin = sourceOrigins[key]
        else {
            return false
        }

        switch permissionCenter.decision(
            for: .automaticDownloads,
            origin: origin,
            in: spaceID
        ) {
        case .grantForSession, .grantPersistently:
            return true
        case .denyForSession, .denyPersistently:
            return false
        case .ask:
            update(download) { ledger, itemID in
                ledger.markAwaitingApproval(itemID)
            }
            let response = await approveAutomaticDownload(
                filename,
                origin,
                spaceNames[key] ?? "this"
            )
            switch response {
            case .allowOnce:
                return true
            case .grantPersistently:
                permissionCenter.setDecision(
                    .grantPersistently,
                    for: .automaticDownloads,
                    origin: origin,
                    in: spaceID
                )
                return true
            case .denyPersistently:
                permissionCenter.setDecision(
                    .denyPersistently,
                    for: .automaticDownloads,
                    origin: origin,
                    in: spaceID
                )
                return false
            }
        }
    }

    private func release(
        _ download: WKDownload,
        authenticationSucceeded: Bool = false
    ) {
        let key = ObjectIdentifier(download)
        let authenticationSession = authenticationSessions.removeValue(forKey: key)
        if authenticationSucceeded {
            Task {
                await authenticationSession?.authenticationSucceeded()
            }
        } else {
            authenticationSession?.authenticationFailed()
        }
        downloads.removeValue(forKey: key)
        itemIDs.removeValue(forKey: key)
        progressObservations.removeValue(forKey: key)
        stagingURLs.removeValue(forKey: key)
        destinationURLs.removeValue(forKey: key)
        securityScopedResources.removeValue(forKey: key)?
            .stopAccessingSecurityScopedResource()
        spaceNames.removeValue(forKey: key)
        spaceIDs.removeValue(forKey: key)
        sourceOrigins.removeValue(forKey: key)
        sourceWebViewIDs.removeValue(forKey: key)
        approvedRetryKeys.remove(key)
        userInitiatedOverrideKeys.remove(key)
    }
}
