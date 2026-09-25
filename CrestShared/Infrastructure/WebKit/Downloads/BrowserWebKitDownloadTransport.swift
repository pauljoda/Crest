import Combine
import Foundation
import WebKit

/// WebKit's download transport for one download center: the `WKDownload`s a
/// WebKit page hands Crest, their destination and automatic-download decisions,
/// progress, authentication and blocked-download retries. The center keeps the
/// engine-neutral records and feedback; this transport reports into it.
@MainActor
final class BrowserWebKitDownloadTransport: NSObject, BrowserDownloadTransport {
    // MARK: - Types

    private struct AutomaticDownloadScope: Hashable {
        let webViewID: ObjectIdentifier
        let origin: SiteOrigin
        let spaceID: SpaceID
    }

    // MARK: - Variables

    private unowned let center: BrowserDownloadCenter

    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var itemIDs: [ObjectIdentifier: UUID] = [:]
    private var progressObservations: [ObjectIdentifier: AnyCancellable] = [:]
    private var transferEstimators: [ObjectIdentifier: DownloadTransferEstimator] = [:]
    private var stagingURLs: [ObjectIdentifier: URL] = [:]
    private var destinationURLs: [ObjectIdentifier: URL] = [:]
    private var securityScopedResources: [ObjectIdentifier: URL] = [:]
    private var spaceNames: [ObjectIdentifier: String] = [:]
    private var spaceIDs: [ObjectIdentifier: SpaceID] = [:]
    private var profileIDs: [ObjectIdentifier: UUID] = [:]
    private var sourceOrigins: [ObjectIdentifier: SiteOrigin] = [:]
    private var permissionRequests:
        [ObjectIdentifier: (controller: BrowserPagePermissionController, generation: UUID)] = [:]
    private var sourceWebViewIDs: [ObjectIdentifier: ObjectIdentifier] = [:]
    /// The core throttle state per page, origin and Space: whether the one
    /// automatic download allowed without asking has been used.
    private var automaticDownloadAllowances: [AutomaticDownloadScope: Bool] = [:]
    private var approvedRetryKeys: Set<ObjectIdentifier> = []
    private var userInitiatedOverrideKeys: Set<ObjectIdentifier> = []
    private var requestedFilenames: [ObjectIdentifier: String] = [:]
    private var forceDestinationPromptKeys: Set<ObjectIdentifier> = []
    private var retryContexts: [UUID: BrowserDownloadRetryContext] = [:]
    private var retryLeases: [UUID: BrowserDownloadRetryLease] = [:]
    private var authenticationSessions: [ObjectIdentifier: BrowserHTTPAuthenticationSession] = [:]

    // MARK: - Initializers

    init(center: BrowserDownloadCenter) {
        self.center = center
        super.init()
    }

    // MARK: - Actions - Transport

    func cancel(_ itemID: UUID) -> Bool {
        if retryLeases.removeValue(forKey: itemID) != nil {
            center.send(CancelDownload(downloadID: itemID, message: "Canceled."))
            return true
        }
        guard let entry = itemIDs.first(where: { $0.value == itemID }),
            let download = downloads[entry.key]
        else { return false }
        download.cancel { _ in }
        removeStagingFile(for: entry.key)
        center.send(CancelDownload(downloadID: itemID, message: "Canceled."))
        release(download)
        return true
    }

    func isTransferring(_ itemID: UUID) -> Bool {
        itemIDs.values.contains(itemID)
    }

    func forget(_ itemID: UUID) {
        retryContexts.removeValue(forKey: itemID)
        retryLeases.removeValue(forKey: itemID)
    }

    func removeTransfers(in assignment: BrowserSpaceRuntimeAssignment) {
        let activeKeys = spaceIDs.compactMap { key, owningSpaceID in
            owningSpaceID == assignment.spaceID ? key : nil
        }
        for key in activeKeys {
            guard let download = downloads[key] else { continue }
            download.cancel { _ in }
            removeStagingFile(for: key)
            release(download)
        }
        retryContexts = retryContexts.filter { _, context in
            context.assignment.profileID != assignment.profileID
                || context.assignment.spaceID != assignment.spaceID
        }
        retryLeases = retryLeases.filter { _, lease in
            lease.assignment.profileID != assignment.profileID
                || lease.assignment.spaceID != assignment.spaceID
        }
        automaticDownloadAllowances = automaticDownloadAllowances.filter {
            $0.key.spaceID != assignment.spaceID
        }
    }

    func setCredentialStorageEnabled(_ isEnabled: Bool, in spaceID: SpaceID) {
        for (key, session) in authenticationSessions where spaceIDs[key] == spaceID {
            session.setCredentialStorageEnabled(isEnabled)
        }
    }

    func resetAutomaticDownloadSequence(forPageView pageView: ObjectIdentifier) {
        automaticDownloadAllowances = automaticDownloadAllowances.filter {
            $0.key.webViewID != pageView
        }
    }

    // MARK: - Actions - Starting

    func start(
        _ download: WKDownload,
        in webView: WKWebView,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String,
        isUserInitiated: Bool?,
        feedbackSource: BrowserDownloadFeedbackSource?,
        suggestedFilenameOverride: String?,
        forcesDestinationPrompt: Bool
    ) {
        guard downloads[ObjectIdentifier(download)] == nil else { return }
        let requestedFilename =
            suggestedFilenameOverride
            ?? download.originalRequest?.url?.lastPathComponent
        let filename = requestedFilename.flatMap { $0.isEmpty ? nil : $0 } ?? "download"
        let itemID = center.begin(profileID: profileID, filename: filename)
        #if os(macOS)
            let feedbackSource = BrowserMacDownloadFeedbackSource.capture(in: webView) ?? feedbackSource
        #endif
        if let feedbackSource {
            center.presentFeedback(
                BrowserDownloadFeedbackEvent(
                    id: itemID,
                    profileID: profileID,
                    spaceID: spaceID,
                    filename: filename,
                    source: feedbackSource
                )
            )
        }
        if let originalRequest = download.originalRequest,
            let request = BrowserDownloadRetryRequestPolicy.replayableRequest(
                from: originalRequest
            )
        {
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
            isUserInitiatedOverride: isUserInitiated,
            suggestedFilenameOverride: suggestedFilenameOverride,
            forcesDestinationPrompt: forcesDestinationPrompt
        )
    }

    // MARK: - Actions - Retry

    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable:
            @escaping @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) async -> Bool? {
        guard let context = retryContexts[itemID],
            context.assignment == assignment,
            let webView = context.webView
        else { return nil }
        guard isAssignmentAvailable(assignment) else { return false }
        let lease = BrowserDownloadRetryLease(
            id: UUID(),
            itemID: itemID,
            profileID: context.assignment.profileID,
            spaceID: context.assignment.spaceID
        )
        retryLeases[itemID] = lease
        center.send(RestartDownload(downloadID: itemID))
        guard !Task.isCancelled else {
            cancelRetryLease(itemID: itemID, lease: lease)
            return false
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                webView.startDownload(using: context.request) {
                    [weak self] download in
                    guard let self else {
                        download.cancel { _ in }
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(
                        returning: finishRetryRegistration(
                            download,
                            itemID: itemID,
                            lease: lease,
                            context: context,
                            webView: webView,
                            isAssignmentAvailable: isAssignmentAvailable
                        )
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRetryLease(itemID: itemID, lease: lease)
            }
        }
    }

    private func finishRetryRegistration(
        _ download: WKDownload,
        itemID: UUID,
        lease: BrowserDownloadRetryLease,
        context: BrowserDownloadRetryContext,
        webView: WKWebView,
        isAssignmentAvailable: @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) -> Bool {
        let currentItem = center.item(itemID)
        let currentContext = retryContexts[itemID]
        guard
            BrowserDownloadRetryRegistrationPolicy.shouldRegister(
                lease: lease,
                currentLease: retryLeases[itemID],
                item: currentItem,
                contextAssignment: currentContext === context
                    ? currentContext?.assignment
                    : nil,
                isAssignmentAvailable: isAssignmentAvailable(lease.assignment)
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
            isUserInitiatedOverride: nil,
            suggestedFilenameOverride: nil,
            forcesDestinationPrompt: false
        )
        return true
    }

    private func cancelRetryLease(
        itemID: UUID,
        lease: BrowserDownloadRetryLease
    ) {
        guard retryLeases[itemID] == lease else { return }
        retryLeases.removeValue(forKey: itemID)
        if center.item(itemID)?.phase == .preparing {
            center.send(BlockAutomaticDownload(downloadID: itemID))
        }
    }

    private func rejectRetryRegistration(
        _ download: WKDownload,
        itemID: UUID,
        lease: BrowserDownloadRetryLease
    ) {
        if retryLeases[itemID] == lease {
            retryLeases.removeValue(forKey: itemID)
            if center.item(itemID)?.phase == .preparing {
                center.send(BlockAutomaticDownload(downloadID: itemID))
            }
        }
        download.cancel { _ in }
    }

    // MARK: - Actions - Registration

    private func register(
        _ download: WKDownload,
        itemID: UUID,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String,
        sourceWebView: WKWebView,
        isUserApprovedRetry: Bool,
        isUserInitiatedOverride: Bool?,
        suggestedFilenameOverride: String?,
        forcesDestinationPrompt: Bool
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
        if let suggestedFilenameOverride {
            requestedFilenames[key] = BrowserDownloadDestination.safeFilename(
                from: suggestedFilenameOverride
            )
        }
        if forcesDestinationPrompt {
            forceDestinationPromptKeys.insert(key)
        }
        spaceNames[key] = spaceName
        spaceIDs[key] = spaceID
        profileIDs[key] = profileID
        sourceWebViewIDs[key] = ObjectIdentifier(sourceWebView)
        if let controller = (sourceWebView.uiDelegate as? any BrowserPagePermissionProviding)?.sitePermissionRequests {
            permissionRequests[key] = (controller, controller.generation)
        }
        let frameOrigin = SiteOrigin(download.originatingFrame.securityOrigin)
        // Automatic downloads belong to the visible site, including files served
        // by its embedded frames or a CDN, so site controls can change the rule.
        if let origin = sourceWebView.url.flatMap(SiteOrigin.init(url:)) {
            sourceOrigins[key] = origin
        } else if !frameOrigin.host.isEmpty {
            sourceOrigins[key] = frameOrigin
        } else if let sourceURL = download.originalRequest?.url,
            let sourceOrigin = SiteOrigin(url: sourceURL)
        {
            sourceOrigins[key] = sourceOrigin
        }
        authenticationSessions[key] = center.makeAuthenticationSession(in: spaceID)
        download.delegate = self
        let progress = download.progress
        progressObservations[key] = Publishers.CombineLatest4(
            progress.publisher(
                for: \.completedUnitCount,
                options: [.initial, .new]
            ),
            progress.publisher(
                for: \.totalUnitCount,
                options: [.initial, .new]
            ),
            progress.publisher(
                for: \.fractionCompleted,
                options: [.initial, .new]
            ),
            progress.publisher(for: \.isPaused, options: [.initial, .new])
        )
        .receive(on: DispatchQueue.main)
        .removeDuplicates { previous, next in
            previous.0 == next.0
                && previous.1 == next.1
                && previous.2 == next.2
                && previous.3 == next.3
        }
        .throttle(
            for: .milliseconds(100),
            scheduler: DispatchQueue.main,
            latest: true
        )
        .sink { [weak self] completed, total, fraction, isPaused in
            MainActor.assumeIsolated {
                guard let self, self.itemIDs[key] != nil else { return }
                var estimator = self.transferEstimators[key]
                let update = self.center.sampleProgress(
                    &estimator,
                    completedUnitCount: completed,
                    totalUnitCount: total,
                    fractionCompleted: fraction,
                    isPaused: isPaused
                )
                self.transferEstimators[key] = estimator
                if let update {
                    self.center.send(
                        RecordDownloadTransfer(
                            downloadID: itemID, telemetry: update.telemetry, progress: update.progress))
                }
            }
        }
    }

    // MARK: - Actions - Delegate

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
        let effectiveSuggestedFilename =
            requestedFilenames[key] ?? suggestedFilename
        let isUserInitiated =
            download.isUserInitiated
            || userInitiatedOverrideKeys.contains(key)
        let verdict = center.riskVerdict(
            suggestedFilename: effectiveSuggestedFilename,
            mimeType: response.mimeType,
            isUserInitiated: isUserInitiated
        )
        let assessment = verdict.assessment
        send(for: download) { AssessDownloadRisk(downloadID: $0, assessment: assessment) }
        let savedDecision: SitePermissionDecision
        if let origin = sourceOrigins[key], let spaceID = spaceIDs[key] {
            savedDecision = center.permissionCenter.decision(
                for: .automaticDownloads,
                origin: origin,
                in: spaceID
            )
        } else {
            savedDecision = .denyPersistently
        }
        let scope: AutomaticDownloadScope? =
            if let origin = sourceOrigins[key],
                let webViewID = sourceWebViewIDs[key],
                let spaceID = spaceIDs[key]
            {
                AutomaticDownloadScope(webViewID: webViewID, origin: origin, spaceID: spaceID)
            } else {
                nil
            }
        // Without a page and origin scope there is no throttle state to keep.
        let automatic = BrowserCorePolicy.automaticDownload(
            isUserInitiated: isUserInitiated,
            isUserApprovedRetry: approvedRetryKeys.contains(key),
            savedDecision: savedDecision,
            hasAllowedAutomaticDownload: scope.flatMap { automaticDownloadAllowances[$0] } ?? false
        )
        if let scope {
            automaticDownloadAllowances[scope] = automatic.hasAllowedAutomaticDownload
        }
        let automaticDownloadAction = automatic.action
        switch automaticDownloadAction.kind {
        case .allow:
            break
        case .deny:
            send(for: download) { BlockAutomaticDownload(downloadID: $0) }
            release(download)
            return nil
        case .requestPermission:
            guard
                await approveAutomaticDownloadIfNeeded(download)
            else {
                send(for: download) { BlockAutomaticDownload(downloadID: $0) }
                release(download)
                return nil
            }
        }
        if verdict.requiresConfirmation {
            // A download that no longer belongs to a profile cannot be approved.
            let approved =
                if let profileID = profileIDs[key] {
                    await center.approveRiskyDownload(
                        assessment,
                        response.url ?? download.originalRequest?.url,
                        spaceNames[key] ?? "this",
                        profileID
                    )
                } else {
                    false
                }
            guard approved else {
                send(for: download) {
                    CancelDownload(downloadID: $0, message: "Canceled before downloading a potentially dangerous file.")
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
        let resolution = await center.resolveDownloadDestination(
            assessment.sanitizedFilename,
            spaceID,
            forceDestinationPromptKeys.contains(key)
        )
        let destination: URL
        let securityScopedURL: URL?
        switch resolution {
        case .destination(let url, let resourceURL):
            destination = url
            securityScopedURL = resourceURL
        case .cancelled:
            send(for: download) { CancelDownload(downloadID: $0, message: "Canceled.") }
            release(download)
            return nil
        case .unavailable:
            #if os(macOS)
                fail(
                    download,
                    message:
                        "The download folder is unavailable. Open Crest Settings > General > System Permissions to check folder access or choose another folder."
                )
            #else
                fail(download, message: "The Downloads folder is unavailable.")
            #endif
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
            suggestedFilename: effectiveSuggestedFilename,
            directory: stagingDirectory
        )
        stagingURLs[key] = staging
        destinationURLs[key] = destination
        if let itemID = itemIDs[key] { center.setDestination(destination, for: itemID) }
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
            let finalByteCount = try? staging.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)
            let quarantine = BrowserDownloadQuarantine(sourceURL: download.originalRequest?.url)
            try BrowserDownloadTransfer.finish(
                from: staging,
                to: destination,
                quarantine: quarantine
            )
            send(for: download) { FinishDownload(downloadID: $0, finalByteCount: finalByteCount) }
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
            ) { [center, spaceName] prompt in
                await center.promptForCredentials(prompt, spaceName)
            }
            completionHandler(resolution.disposition, resolution.credential)
        }
    }

    // MARK: - Actions - Bookkeeping

    private func fail(_ download: WKDownload, message: String) {
        removeStagingFile(for: ObjectIdentifier(download))
        send(for: download) { FailDownload(downloadID: $0, message: message) }
    }

    private func removeStagingFile(for key: ObjectIdentifier) {
        guard let stagingURL = stagingURLs[key] else { return }
        try? FileManager.default.removeItem(at: stagingURL)
    }

    /// Sends the intent `make` builds for `download`'s record, if it still has one.
    private func send<Event: Intent>(for download: WKDownload, _ make: (UUID) -> Event) {
        guard let itemID = itemIDs[ObjectIdentifier(download)] else { return }
        center.send(make(itemID))
    }

    private func approveAutomaticDownloadIfNeeded(
        _ download: WKDownload
    ) async -> Bool {
        let key = ObjectIdentifier(download)
        guard let spaceID = spaceIDs[key],
            let origin = sourceOrigins[key]
        else {
            return false
        }
        let permissionCenter = center.permissionCenter

        let decision = permissionCenter.decision(for: .automaticDownloads, origin: origin, in: spaceID)
        guard decision.verdict == .ask else { return decision.grants }
        send(for: download) { AwaitDownloadApproval(downloadID: $0) }
        guard let request = permissionRequests[key],
            request.generation == request.controller.generation
        else { return false }
        let response = await request.controller.response(
            to: .automaticDownloads, origin: origin, topLevelOrigin: origin,
            spaceName: spaceNames[key] ?? "this"
        )
        guard itemIDs[key] != nil, request.generation == request.controller.generation else { return false }
        let latest = permissionCenter.decision(for: .automaticDownloads, origin: origin, in: spaceID)
        guard !latest.denies else { return false }
        if let savedDecision = response.savedDecision {
            permissionCenter.setDecision(savedDecision, for: .automaticDownloads, origin: origin, in: spaceID)
        }
        return response.grants
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
        transferEstimators.removeValue(forKey: key)
        stagingURLs.removeValue(forKey: key)
        destinationURLs.removeValue(forKey: key)
        securityScopedResources.removeValue(forKey: key)?
            .stopAccessingSecurityScopedResource()
        spaceNames.removeValue(forKey: key)
        spaceIDs.removeValue(forKey: key)
        profileIDs.removeValue(forKey: key)
        sourceOrigins.removeValue(forKey: key)
        sourceWebViewIDs.removeValue(forKey: key)
        permissionRequests.removeValue(forKey: key)
        approvedRetryKeys.remove(key)
        userInitiatedOverrideKeys.remove(key)
        requestedFilenames.removeValue(forKey: key)
        forceDestinationPromptKeys.remove(key)
    }
}
