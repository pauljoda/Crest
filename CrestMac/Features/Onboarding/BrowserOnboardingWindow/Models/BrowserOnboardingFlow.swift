import Foundation
import Observation

@Observable
@MainActor
final class BrowserOnboardingFlow {
    let browser: BrowserStore

    private(set) var request: BrowserOnboardingRequest
    private(set) var state: BrowserOnboardingFlowState
    private(set) var installedSources: [BrowserInstalledImportSource] = []
    private(set) var selectedImportApplications: Set<BrowserImportApplication> = []
    private(set) var importQueue = BrowserImportQueue(applications: [])
    private(set) var selectedApplication: BrowserImportApplication?
    private(set) var plan: BrowserImportReviewPlan?
    private(set) var manualPlan: BrowserManualSetupPlan?
    private(set) var passwordCountsBySourceSpace: [SpaceID: Int] = [:]
    private(set) var currentImportPayload: BrowserDetectedImportPayload?
    private(set) var failure: BrowserOnboardingFailure?
    private(set) var completionSummary: LocalizedStringResource?
    private(set) var isChoosingDataAccess = false
    private(set) var isCommittingImport = false

    @ObservationIgnored private let sourceDiscovery: any BrowserInstalledImportSourceDiscovering
    @ObservationIgnored private let dataAccessProvider: any BrowserOnboardingDataAccessProviding
    @ObservationIgnored private let importCommitter: any BrowserOnboardingImportCommitting
    @ObservationIgnored private let importReadCoordinator: BrowserOnboardingImportReadCoordinator
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var finalizationTask:
        Task<
            Result<BrowserPasswordImportResult, any Error>,
            Never
        >?
    @ObservationIgnored private var pendingResetRequest: BrowserOnboardingRequest?
    @ObservationIgnored private var operationGeneration = 0

    var step: BrowserOnboardingStep { state.step }

    var isReading: Bool {
        importReadCoordinator.isInFlight
    }

    var isImportSelectionLocked: Bool {
        isReading || isChoosingDataAccess || isCommittingImport
    }

    var nextImportStep: BrowserOnboardingStep {
        if plan != nil { return .review }
        if manualPlan != nil { return .manualSetup }
        return .importBrowser
    }

    var importReviewActionTitle: LocalizedStringResource {
        importQueue.hasMoreAfterCurrent
            ? LocalizedStringResource(
                "Import & Continue",
                comment:
                    "Button that imports the current browser and continues to the next selected browser."
            )
            : LocalizedStringResource(
                "Import Reviewed Data",
                comment:
                    "Button that imports the reviewed data from the final selected browser."
            )
    }

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering =
            LiveBrowserInstalledImportSourceDiscovery(),
        dataAccessProvider: any BrowserOnboardingDataAccessProviding =
            LiveBrowserOnboardingDataAccessProvider(),
        importReader: any BrowserOnboardingImportReading =
            LiveBrowserOnboardingImportReader(),
        importCommitter: any BrowserOnboardingImportCommitting =
            LiveBrowserOnboardingImportCommitter()
    ) {
        self.request = request
        self.browser = browser
        self.sourceDiscovery = sourceDiscovery
        self.dataAccessProvider = dataAccessProvider
        self.importCommitter = importCommitter
        importReadCoordinator = BrowserOnboardingImportReadCoordinator(
            reader: importReader
        )

        let initialManualPlan =
            request.entryPoint == .manualSetup
            ? BrowserManualSetupPlan(existing: browser.session)
            : nil
        manualPlan = initialManualPlan
        state = Self.initialState(for: request.entryPoint)
    }

    func discoverInstalledSources() {
        installedSources = sourceDiscovery.installedSources()
    }

    func reset(for request: BrowserOnboardingRequest) {
        guard finalizationTask == nil else {
            pendingResetRequest = request
            operationGeneration &+= 1
            return
        }
        applyReset(for: request)
    }

    private func applyReset(for request: BrowserOnboardingRequest) {
        invalidateOperations()
        self.request = request
        selectedImportApplications = []
        importQueue = BrowserImportQueue(applications: [])
        selectedApplication = nil
        plan = nil
        passwordCountsBySourceSpace = [:]
        currentImportPayload = nil
        failure = nil
        completionSummary = nil

        manualPlan =
            request.entryPoint == .manualSetup
            ? BrowserManualSetupPlan(existing: browser.session)
            : nil
        state = Self.initialState(for: request.entryPoint)
    }

    func cancelOperations() {
        guard finalizationTask == nil else { return }
        let activeState = state
        invalidateOperations()
        switch activeState {
        case .reading:
            state = .importSelection
        case .committing(let application):
            state = .reviewing(application)
        case .welcome, .featureSpaces, .featureTabs, .featureSync,
            .importSelection, .reviewing, .manualSetup, .complete:
            break
        }
    }

    func show(_ step: BrowserOnboardingStep) {
        guard !isImportSelectionLocked else { return }
        switch step {
        case .welcome:
            state = .welcome
        case .featureSpaces:
            state = .featureSpaces
        case .featureTabs:
            state = .featureTabs
        case .featureSync:
            state = .featureSync
        case .importBrowser:
            state = .importSelection
        case .review:
            guard let application = selectedApplication else { return }
            state = .reviewing(application)
        case .manualSetup:
            beginManualSetup()
        case .complete:
            state = .complete
        }
    }

    func toggleImportSelection(_ application: BrowserImportApplication) {
        guard !isImportSelectionLocked else { return }
        if selectedImportApplications.contains(application) {
            selectedImportApplications.remove(application)
        } else {
            selectedImportApplications.insert(application)
        }
        importQueue = BrowserImportQueue(
            selected: selectedImportApplications,
            availableOrder: installedSources.map(\.application)
        )
        plan = nil
        selectedApplication = nil
        currentImportPayload = nil
        passwordCountsBySourceSpace = [:]
        failure = nil
        state = .importSelection
    }

    func continueImportQueue() {
        guard !isImportSelectionLocked else { return }
        guard !selectedImportApplications.isEmpty else {
            beginManualSetup()
            return
        }

        synchronizeImportQueueWithSelection()
        guard let application = importQueue.current,
            let source = installedSources.first(where: {
                $0.application == application
            })
        else {
            failure = .sourceUnavailable
            state = .importSelection
            return
        }
        beginImport(from: source)
    }

    func retryImport() {
        guard failure != nil, !isImportSelectionLocked else { return }
        failure = nil
        continueImportQueue()
    }

    func cancelImportRead() {
        importReadCoordinator.cancel()
        guard case .reading = state else { return }
        state = .importSelection
        failure = nil
    }

    func beginManualSetup() {
        guard !isCommittingImport else { return }
        abandonImportPreparation()
        prepareManualSetup()
    }

    private func prepareManualSetup() {
        importReadCoordinator.cancel()
        var updated = manualPlan ?? BrowserManualSetupPlan(existing: browser.session)
        updated.reconcile(with: browser.session)
        manualPlan = updated
        failure = nil
        state = .manualSetup
    }

    func updatePlan(_ plan: BrowserImportReviewPlan) {
        guard !isCommittingImport else { return }
        self.plan = plan
    }

    func updateManualPlan(_ plan: BrowserManualSetupPlan) {
        manualPlan = plan
    }

    func setDestination(
        _ destination: BrowserImportDestination,
        for sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setDestination(destination, for: sourceSpaceID)
        plan = updated
    }

    func setIncluded(
        _ tabID: TabID,
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setTab(tabID, isIncluded: isIncluded, in: sourceSpaceID)
        plan = updated
    }

    func setIncluded(
        _ tabIDs: Set<TabID>,
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setTabs(tabIDs, isIncluded: isIncluded, in: sourceSpaceID)
        plan = updated
    }

    func setPlacement(
        _ placement: TabPlacement,
        for tabID: TabID,
        in sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setPlacement(placement, for: tabID, in: sourceSpaceID)
        plan = updated
    }

    func setSpaceIncluded(
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setSpace(sourceSpaceID, isIncluded: isIncluded)
        plan = updated
    }

    func setPasswordsIncluded(
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard !isCommittingImport, var updated = plan else { return }
        updated.setPasswords(isIncluded, in: sourceSpaceID)
        plan = updated
    }

    func commitManualSetup() {
        guard let manualPlan, !isCommittingImport else { return }
        do {
            try browser.commitManualSetup(manualPlan)
            let addedTabs = manualPlan.spaces.reduce(0) {
                $0 + $1.addedTabs.count
            }
            let newSpaces = manualPlan.spaces.filter(\.isNew).count
            completionSummary = BrowserOnboardingSummary.completedManualSetup(
                newSpaceCount: newSpaces,
                addedTabCount: addedTabs
            )
            self.manualPlan = nil
            plan = nil
            failure = nil
            state = .complete
        } catch {
            failure = .manualCommit(error.localizedDescription)
        }
    }

    func commitReviewedImport() {
        guard let plan, !isCommittingImport else { return }
        guard let application = selectedApplication else { return }
        guard plan.hasIncludedSpaces else {
            failure = .importCommit(
                BrowserImportReviewPlan.ValidationError.noIncludedSpaces
                    .localizedDescription
            )
            return
        }
        let generation = operationGeneration
        state = .committing(application)
        failure = nil
        isCommittingImport = true

        let payload = currentImportPayload
        let passwordCounts = passwordCountsBySourceSpace
        commitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performImportCommit(
                plan: plan,
                application: application,
                payload: payload,
                passwordCountsBySourceSpace: passwordCounts,
                generation: generation
            )
        }
    }

    func selectedReview(
        id: SpaceID?
    ) -> BrowserImportSpaceReview? {
        guard let plan else { return nil }
        return plan.spaces.first { $0.id == id } ?? plan.spaces.first
    }

    func passwordCountLabel(
        for review: BrowserImportSpaceReview
    ) -> LocalizedStringResource {
        BrowserOnboardingSummary.passwordCount(
            passwordCountsBySourceSpace[review.id, default: 0]
        )
    }

    func reviewSummary() -> LocalizedStringResource? {
        guard let plan else { return nil }
        let includedTabCount = plan.spaces.reduce(0) {
            $0 + $1.includedTabIDs.count
        }
        let passwordCount = plan.spaces.reduce(0) { partial, review in
            partial
                + (review.includesPasswords
                    ? passwordCountsBySourceSpace[review.id, default: 0]
                    : 0)
        }
        return BrowserOnboardingSummary.review(
            tabCount: includedTabCount,
            passwordCount: passwordCount,
            overflowTabCount: plan.overflowTabIDs(in: browser.session).count
        )
    }

    func previewDestinationSpace(
        for review: BrowserImportSpaceReview
    ) -> BrowserSpace? {
        guard let plan,
            let preview = try? plan.preview(mergingInto: browser.session)
        else {
            return nil
        }
        switch review.destination {
        case .newSpace:
            return preview.space(id: review.id)
        case .existing(let id):
            return preview.space(id: id)
        }
    }

    func customizationPreviewSpace(_ spaceID: SpaceID) -> BrowserSpace? {
        guard let review = plan?.spaces.first(where: { $0.id == spaceID }) else {
            return nil
        }
        return previewDestinationSpace(for: review)
    }

    func duplicateDestinationName(
        for review: BrowserImportSpaceReview
    ) -> String? {
        guard case .existing(let id) = review.destination else { return nil }
        return browser.session.space(id: id)?.name
    }

    func destinationName(
        for destination: BrowserImportDestination
    ) -> String {
        switch destination {
        case .newSpace:
            String(localized: "New Space")
        case .existing(let id):
            browser.session.space(id: id)?.name
                ?? String(localized: "Existing Space")
        }
    }

    func reviewProgressLabel(
        for review: BrowserImportSpaceReview
    ) -> String {
        guard let plan else { return "" }
        let index = plan.spaces.firstIndex(where: { $0.id == review.id }) ?? 0
        let spaceProgress = String(
            localized: "Space \(index + 1) of \(plan.spaces.count)"
        )
        return importQueue.progressLabel.map {
            String(localized: "\($0) · \(spaceProgress)")
        } ?? spaceProgress
    }

    func importAccessLabel(
        for source: BrowserInstalledImportSource
    ) -> String {
        if source.hasReadableDetectedData {
            return detectedDataLabel(source)
        }
        if dataAccessProvider.hasSavedAccess(for: source.application) {
            return String(localized: "Access saved · Ready to review")
        }
        return String(localized: "One-time macOS permission · No folder search")
    }

    private static func initialState(
        for entryPoint: BrowserOnboardingEntryPoint
    ) -> BrowserOnboardingFlowState {
        switch entryPoint {
        case .firstRun:
            .welcome
        case .importBrowser:
            .importSelection
        case .manualSetup:
            .manualSetup
        }
    }

    private func synchronizeImportQueueWithSelection() {
        let remainingSelection = Set(importQueue.remaining)
        guard
            importQueue.isComplete
                || remainingSelection != selectedImportApplications
        else {
            return
        }
        importQueue = BrowserImportQueue(
            selected: selectedImportApplications,
            availableOrder: installedSources.map(\.application)
        )
    }

    private func beginImport(from source: BrowserInstalledImportSource) {
        failure = nil
        selectedApplication = source.application

        if source.hasReadableDetectedData {
            readImport(source.detectedPayload)
            return
        }

        if let access = dataAccessProvider.resolve(for: source.application) {
            let profiles = BrowserImportDataLocator.importProfiles(
                for: source.application,
                dataDirectory: access.url
            )
            if !profiles.isEmpty {
                readImport(
                    BrowserDetectedImportPayload(
                        application: source.application,
                        profiles: profiles,
                        passwordStores: BrowserImportDataLocator.passwordStores(
                            for: source.application,
                            dataDirectory: access.url
                        )
                    ),
                    activeDirectoryAccess: access
                )
                return
            }
            access.stopAccessing()
            dataAccessProvider.clear(for: source.application)
        }

        chooseBrowserDataAccess(for: source.application)
    }

    private func chooseBrowserDataAccess(
        for application: BrowserImportApplication
    ) {
        failure = nil
        isChoosingDataAccess = true
        let generation = operationGeneration
        dataAccessProvider.chooseDataFolder(for: application) {
            [weak self] folderURL in
            guard let self,
                operationGeneration == generation
            else { return }
            isChoosingDataAccess = false
            guard selectedApplication == application,
                selectedImportApplications.contains(application),
                state == .importSelection,
                let folderURL
            else { return }
            let access = BrowserImportDataDirectoryAccess(url: folderURL)
            let profiles = BrowserImportDataLocator.importProfiles(
                for: application,
                dataDirectory: folderURL
            )
            guard !profiles.isEmpty else {
                access.stopAccessing()
                failure = .dataDirectory(application)
                return
            }
            try? dataAccessProvider.remember(folderURL, for: application)
            readImport(
                BrowserDetectedImportPayload(
                    application: application,
                    profiles: profiles,
                    passwordStores: BrowserImportDataLocator.passwordStores(
                        for: application,
                        dataDirectory: folderURL
                    )
                ),
                activeDirectoryAccess: access
            )
        }
    }

    private func readImport(
        _ payload: BrowserDetectedImportPayload,
        activeDirectoryAccess: BrowserImportDataDirectoryAccess? = nil
    ) {
        failure = nil
        isChoosingDataAccess = false
        selectedApplication = payload.application
        currentImportPayload = payload
        state = .reading(payload.application)
        let generation = operationGeneration
        importReadCoordinator.startReading(
            payload,
            onFinish: {
                activeDirectoryAccess?.stopAccessing()
            },
            completion: { [weak self] result in
                guard let self, operationGeneration == generation else { return }
                completeRead(result)
            }
        )
    }

    private func completeRead(
        _ result: Result<BrowserOnboardingImportReadOutput, any Error>
    ) {
        switch result {
        case .success(let output):
            buildReviewPlan(
                output.imported,
                passwordCandidates: output.passwordCandidates,
                application: output.payload.application
            )
        case .failure(let error):
            failure = .read(error.localizedDescription)
            state = .importSelection
        }
    }

    private func buildReviewPlan(
        _ imported: BrowserPortableImport,
        passwordCandidates: [BrowserPasswordImportCandidate],
        application: BrowserImportApplication
    ) {
        let reviewPlan = BrowserImportReviewPlan(
            imported: imported,
            existing: browser.session
        )
        passwordCountsBySourceSpace = mappedPasswordCounts(
            passwordCandidates,
            in: reviewPlan
        )
        plan = reviewPlan
        failure = nil
        state = .reviewing(application)
    }

    private func performImportCommit(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int],
        generation: Int
    ) async {
        defer { finishImportCommit(generation: generation) }

        do {
            let preparedImport = try await importCommitter.prepare(
                plan: plan,
                application: application,
                payload: payload,
                passwordCountsBySourceSpace: passwordCountsBySourceSpace
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }

            // Finalization is the point of no return. It runs in its own task so
            // reset and window dismissal cannot leave the session or Keychain
            // credential import only partially applied.
            let importCommitter = self.importCommitter
            let browser = self.browser
            let finalizationTask:
                Task<
                    Result<BrowserPasswordImportResult, any Error>,
                    Never
                > = Task { @MainActor in
                    do {
                        return .success(
                            try await importCommitter.finalize(
                                plan: plan,
                                preparedImport: preparedImport,
                                browser: browser
                            )
                        )
                    } catch {
                        return .failure(error)
                    }
                }
            self.finalizationTask = finalizationTask
            let outcome = await finalizationTask.value
            let didApplyPendingReset = finishImportFinalization()
            guard !didApplyPendingReset else { return }

            switch outcome {
            case .success(let passwordResult):
                guard operationGeneration == generation else { return }
                completeImport(
                    plan: plan,
                    application: application,
                    passwordResult: passwordResult
                )
            case .failure(let error):
                guard operationGeneration == generation else { return }
                failure = .importCommit(error.localizedDescription)
                state = .reviewing(application)
            }
        } catch is CancellationError {
            return
        } catch {
            guard operationGeneration == generation else { return }
            failure = .importCommit(error.localizedDescription)
            state = .reviewing(application)
        }
    }

    private func finishImportCommit(generation: Int) {
        guard finalizationTask == nil else { return }
        guard operationGeneration == generation else { return }
        commitTask = nil
        isCommittingImport = false
    }

    private func finishImportFinalization() -> Bool {
        finalizationTask = nil
        commitTask = nil
        isCommittingImport = false
        guard let pendingResetRequest else { return false }
        self.pendingResetRequest = nil
        applyReset(for: pendingResetRequest)
        return true
    }

    private func completeImport(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        passwordResult: BrowserPasswordImportResult
    ) {
        let selectedTabCount = plan.spaces.reduce(0) {
            $0 + $1.includedTabIDs.count
        }
        completionSummary = BrowserOnboardingSummary.completedImport(
            tabCount: selectedTabCount,
            passwordCount: passwordResult.importedCount,
            spaceCount: plan.spaces.filter(\.isIncluded).count
        )

        selectedImportApplications.remove(application)
        self.plan = nil
        selectedApplication = nil
        currentImportPayload = nil
        passwordCountsBySourceSpace = [:]
        failure = nil

        if importQueue.advance() {
            state = .importSelection
            let generation = operationGeneration
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, operationGeneration == generation else { return }
                continueImportQueue()
            }
            return
        }

        let destination = BrowserMacOnboardingPolicy.destinationAfterImport(
            for: request.entryPoint
        )
        if destination == .manualSetup {
            prepareManualSetup()
        } else {
            state = .complete
        }
    }

    private func mappedPasswordCounts(
        _ candidates: [BrowserPasswordImportCandidate],
        in plan: BrowserImportReviewPlan
    ) -> [SpaceID: Int] {
        var counts: [SpaceID: Int] = [:]
        for candidate in candidates {
            for sourceSpaceID in BrowserPasswordImportCommitter.sourceSpaceIDs(
                for: candidate,
                plan: plan,
                respectsPasswordSelection: false
            ) {
                counts[sourceSpaceID, default: 0] += 1
            }
        }
        return counts
    }

    private func invalidateOperations() {
        operationGeneration &+= 1
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
        commitTask?.cancel()
        commitTask = nil
        if finalizationTask == nil {
            isCommittingImport = false
        }
    }

    private func abandonImportPreparation() {
        guard isReading || isChoosingDataAccess else { return }
        operationGeneration &+= 1
        importReadCoordinator.cancel()
        isChoosingDataAccess = false
    }

    private func detectedDataLabel(
        _ source: BrowserInstalledImportSource
    ) -> String {
        let count = source.detectedPayload.profiles.count
        if count > 1 {
            return String(localized: "\(count) profiles found · Review them")
        }
        return String(localized: "Browser data found · Review it")
    }
}
