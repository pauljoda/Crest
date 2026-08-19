import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserOnboardingFlowTests: XCTestCase {
    func testEntryPointsChooseExhaustiveInitialStates() {
        let firstRun = makeFlow(entryPoint: .firstRun)
        let browserImport = makeFlow(entryPoint: .importBrowser)
        let manualSetup = makeFlow(entryPoint: .manualSetup)

        XCTAssertEqual(firstRun.state, .welcome)
        XCTAssertEqual(browserImport.state, .importSelection)
        XCTAssertEqual(manualSetup.state, .manualSetup)
        XCTAssertNil(firstRun.manualPlan)
        XCTAssertNil(browserImport.manualPlan)
        XCTAssertNotNil(manualSetup.manualPlan)
    }

    func testDiscoveryPublishesInstalledSourcesInDetectorOrder() {
        let sources = [source(.arc), source(.safari)]
        let flow = makeFlow(sourceDiscovery: StubSourceDiscovery(sources: sources))

        flow.discoverInstalledSources()

        XCTAssertEqual(flow.installedSources.map(\.application), [.arc, .safari])
        XCTAssertEqual(flow.state, .importSelection)
    }

    func testSuccessfulReadBuildsAReviewAndSelectsItsFirstSpace() async throws {
        let importedSpace = makeSpace(name: "Imported")
        let output = readOutput(
            application: .safari,
            import: portableImport(spaces: [importedSpace])
        )
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(result: .success(output))
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)

        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }

        XCTAssertEqual(flow.plan?.spaces.map(\.id), [importedSpace.id])
        XCTAssertNil(flow.failure)
    }

    func testFailedReadCanRetryWithoutRebuildingTheImportSelection() async {
        let reader = SequencedImportReader(
            results: [
                .failure(TestFailure.read),
                .success(
                    readOutput(
                        application: .chrome,
                        import: portableImport(spaces: [makeSpace(name: "Retry")])
                    )
                ),
            ]
        )
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.chrome)]),
            reader: reader
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)

        flow.continueImportQueue()
        await waitUntil { flow.failure != nil }

        XCTAssertEqual(flow.state, .importSelection)
        XCTAssertEqual(
            flow.failure?.message,
            .verbatim(TestFailure.read.localizedDescription)
        )
        XCTAssertEqual(flow.selectedImportApplications, [.chrome])

        flow.retryImport()
        await waitUntil { flow.state == .reviewing(.chrome) }

        XCTAssertNil(flow.failure)
        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 2)
    }

    func testCancellationPreventsALateReadFromPublishingAReview() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: reader
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.arc)
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        flow.cancelImportRead()
        await reader.complete(
            readOutput(
                application: .arc,
                import: portableImport(spaces: [makeSpace(name: "Too Late")])
            )
        )
        await Task.yield()

        XCTAssertEqual(flow.state, .importSelection)
        XCTAssertNil(flow.plan)
        XCTAssertNil(flow.failure)
    }

    func testNavigationDoesNotUnlockASuspendedRead() async {
        let reader = SuspendedFlowImportReader()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: reader
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.arc)
        flow.continueImportQueue()
        await reader.waitUntilStarted()

        flow.show(.featureSync)
        XCTAssertTrue(flow.isReading)
        XCTAssertEqual(flow.state, .reading(.arc))
        flow.show(.importBrowser)
        flow.toggleImportSelection(.arc)

        XCTAssertEqual(flow.selectedImportApplications, [.arc])
        await reader.complete(
            readOutput(
                application: .arc,
                import: portableImport(
                    spaces: [makeSpace(name: "Still Selected")]
                )
            )
        )
        await waitUntil { flow.state == .reviewing(.arc) }
    }

    func testResetInvalidatesAStaleDataAccessCallback() {
        let dataAccessProvider = SuspendedDataAccessProvider()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(
                sources: [source(.chrome, hasDetectedData: false)]
            ),
            dataAccessProvider: dataAccessProvider
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        XCTAssertTrue(dataAccessProvider.hasPendingRequest)

        flow.reset(
            for: BrowserOnboardingRequest(entryPoint: .manualSetup)
        )
        dataAccessProvider.complete(
            with: URL(fileURLWithPath: "/tmp/obsolete-browser-data")
        )

        XCTAssertEqual(flow.state, .manualSetup)
        XCTAssertNil(flow.failure)
        XCTAssertNil(flow.plan)
        XCTAssertFalse(flow.isReading)
    }

    func testUnreadableDetectedSafariDataRequestsFolderAccessBeforeReading() {
        let dataAccessProvider = SuspendedDataAccessProvider()
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(
                sources: [
                    source(
                        .safari,
                        detectedDataURL: missingURL
                    )
                ]
            ),
            dataAccessProvider: dataAccessProvider
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)

        flow.continueImportQueue()

        XCTAssertTrue(dataAccessProvider.hasPendingRequest)
        XCTAssertTrue(flow.isChoosingDataAccess)
        XCTAssertFalse(flow.isReading)
        XCTAssertEqual(flow.state, .importSelection)
    }

    func testManualSetupAbandonsAPendingDataAccessCallback() {
        let dataAccessProvider = SuspendedDataAccessProvider()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(
                sources: [source(.chrome, hasDetectedData: false)]
            ),
            dataAccessProvider: dataAccessProvider
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.chrome)
        flow.continueImportQueue()
        XCTAssertTrue(dataAccessProvider.hasPendingRequest)

        flow.beginManualSetup()
        dataAccessProvider.complete(
            with: URL(fileURLWithPath: "/tmp/obsolete-browser-data")
        )

        XCTAssertEqual(flow.state, .manualSetup)
        XCTAssertNil(flow.failure)
        XCTAssertNil(flow.plan)
        XCTAssertFalse(flow.isChoosingDataAccess)
        XCTAssertFalse(flow.isReading)
    }

    func testCommitAdvancesToTheNextSelectedBrowser() async {
        let first = makeSpace(name: "Arc")
        let second = makeSpace(name: "Safari")
        let reader = SequencedImportReader(
            results: [
                .success(
                    readOutput(
                        application: .arc,
                        import: portableImport(spaces: [first])
                    )
                ),
                .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(spaces: [second])
                    )
                ),
            ]
        )
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(
                sources: [source(.arc), source(.safari)]
            ),
            reader: reader
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.arc)
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.arc) }

        flow.commitReviewedImport()
        await waitUntil { flow.state == .reviewing(.safari) }

        XCTAssertEqual(flow.importQueue.current, .safari)
        XCTAssertEqual(flow.plan?.spaces.map(\.id), [second.id])
        XCTAssertTrue(flow.browser.session.spaces.contains { $0.name == "Arc" })
    }

    func testFinalCommitCompletesAnExplicitImportRequest() async {
        let imported = makeSpace(name: "Imported")
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(spaces: [imported])
                    )
                )
            )
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }

        flow.commitReviewedImport()
        await waitUntil { flow.state == .complete }

        XCTAssertEqual(flow.state, .complete)
        XCTAssertEqual(
            flow.completionSummary.map { localized($0) },
            "Imported 1 reviewed tab across 1 Space."
        )
        XCTAssertTrue(flow.browser.session.spaces.contains { $0.id == imported.id })
    }

    func testFinalFirstRunImportAdvancesToCompletion() async {
        let flow = makeFlow(
            entryPoint: .firstRun,
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(
                            spaces: [makeSpace(name: "First Run Import")]
                        )
                    )
                )
            )
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }

        flow.commitReviewedImport()
        await waitUntil { flow.state == .complete }

        XCTAssertEqual(flow.state, .complete)
        XCTAssertNil(flow.manualPlan)
    }

    func testCommitRequiresAtLeastOneIncludedSpace() async throws {
        let imported = makeSpace(name: "Excluded")
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.arc)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .arc,
                        import: portableImport(spaces: [imported])
                    )
                )
            )
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.arc)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.arc) }
        let originalSession = flow.browser.session
        let spaceID = try XCTUnwrap(flow.plan?.spaces.first?.id)
        flow.setSpaceIncluded(false, in: spaceID)

        flow.commitReviewedImport()

        XCTAssertEqual(flow.state, .reviewing(.arc))
        XCTAssertEqual(
            flow.failure?.message,
            .verbatim("Choose at least one Space to import.")
        )
        XCTAssertFalse(flow.isCommittingImport)
        XCTAssertEqual(flow.browser.session, originalSession)
    }

    func testFailedCommitRetainsTheReviewAndCanRetry() async {
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(
                            spaces: [makeSpace(name: "Commit Retry")]
                        )
                    )
                )
            )
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }
        let originalSession = flow.browser.session
        flow.browser.session = sessionAtSpaceLimit(from: originalSession)

        flow.commitReviewedImport()
        await waitUntil { flow.failure != nil }

        XCTAssertEqual(flow.state, .reviewing(.safari))
        XCTAssertNotNil(flow.plan)
        guard case .importCommit? = flow.failure else {
            return XCTFail("Expected an import commit failure")
        }

        flow.browser.session = originalSession
        flow.commitReviewedImport()
        await waitUntil { flow.state == .complete }

        XCTAssertEqual(flow.state, .complete)
        XCTAssertNil(flow.failure)
    }

    func testNavigationCannotStartAnOverlappingCommit() async {
        let committer = SuspendedImportCommitter()
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(
                            spaces: [makeSpace(name: "One Commit")]
                        )
                    )
                )
            ),
            importCommitter: committer
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }

        flow.commitReviewedImport()
        await committer.waitUntilStarted()
        flow.show(.importBrowser)
        flow.commitReviewedImport()
        flow.toggleImportSelection(.safari)
        guard let review = flow.plan?.spaces.first else {
            return XCTFail("Expected an import review")
        }
        flow.setSpaceIncluded(false, in: review.id)

        XCTAssertTrue(flow.isCommittingImport)
        XCTAssertEqual(flow.state, .committing(.safari))
        XCTAssertEqual(flow.selectedImportApplications, [.safari])
        XCTAssertEqual(
            flow.plan?.spaces.first(where: { $0.id == review.id })?.isIncluded,
            true
        )
        XCTAssertEqual(committer.callCount, 1)

        committer.complete()
        await waitUntil { flow.state == .complete }
        XCTAssertFalse(flow.isCommittingImport)
    }

    func testResetCancelsACommitWithoutPublishingItsLateCompletion() async {
        let committer = SuspendedImportCommitter()
        let staleSpace = makeSpace(name: "Stale Commit")
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(spaces: [staleSpace])
                    )
                )
            ),
            importCommitter: committer
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }
        flow.commitReviewedImport()
        await committer.waitUntilStarted()

        flow.reset(
            for: BrowserOnboardingRequest(entryPoint: .manualSetup)
        )
        committer.complete()
        await Task.yield()

        XCTAssertEqual(flow.state, .manualSetup)
        XCTAssertFalse(flow.isCommittingImport)
        XCTAssertNil(flow.failure)
        XCTAssertFalse(flow.browser.session.spaces.contains { $0.id == staleSpace.id })
    }

    func testResetDuringFinalizationLetsTheCommittedMutationFinish() async {
        let committer = PostMutationSuspendedImportCommitter()
        let committedSpace = makeSpace(name: "Committed Before Reset")
        let flow = makeFlow(
            sourceDiscovery: StubSourceDiscovery(sources: [source(.safari)]),
            reader: ImmediateImportReader(
                result: .success(
                    readOutput(
                        application: .safari,
                        import: portableImport(spaces: [committedSpace])
                    )
                )
            ),
            importCommitter: committer
        )
        flow.discoverInstalledSources()
        flow.toggleImportSelection(.safari)
        flow.continueImportQueue()
        await waitUntil { flow.state == .reviewing(.safari) }
        flow.commitReviewedImport()
        await committer.waitUntilFinalizationStarted()

        XCTAssertTrue(
            flow.browser.session.spaces.contains { $0.id == committedSpace.id }
        )
        flow.reset(
            for: BrowserOnboardingRequest(entryPoint: .manualSetup)
        )
        XCTAssertTrue(flow.isCommittingImport)
        XCTAssertEqual(flow.state, .committing(.safari))

        committer.completeFinalization()
        await waitUntil {
            !flow.isCommittingImport && flow.state == .manualSetup
        }

        XCTAssertEqual(flow.state, .manualSetup)
        XCTAssertNil(flow.failure)
        XCTAssertTrue(
            flow.browser.session.spaces.contains { $0.id == committedSpace.id }
        )
    }

    func testManualCommitCompletesWithAPluralAwareSummary() throws {
        let flow = makeFlow(entryPoint: .manualSetup)
        var plan = try XCTUnwrap(flow.manualPlan)
        let spaceID = try XCTUnwrap(plan.spaces.first?.id)
        _ = try plan.addTab(
            input: "example.com",
            placement: .current,
            to: spaceID
        )
        flow.updateManualPlan(plan)

        flow.commitManualSetup()

        XCTAssertEqual(flow.state, .complete)
        XCTAssertEqual(
            flow.completionSummary.map { localized($0) },
            "Updated your Spaces and added 1 tab."
        )
    }

    func testSummaryPolicyHandlesSingularAndPluralCountsWithoutFragments() {
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.review(
                    tabCount: 1,
                    passwordCount: 1,
                    overflowTabCount: 1
                )
            ),
            "1 tab selected · 1 password · 1 pinned tab moves to a saved folder"
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.review(
                    tabCount: 2,
                    passwordCount: 2,
                    overflowTabCount: 2
                )
            ),
            "2 tabs selected · 2 passwords · 2 pinned tabs move to a saved folder"
        )
        XCTAssertEqual(
            localized(BrowserOnboardingSummary.passwordCount(1)),
            "1 password"
        )
        XCTAssertEqual(
            localized(BrowserOnboardingSummary.passwordCount(2)),
            "2 passwords"
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 1,
                    passwordCount: 1,
                    spaceCount: 1
                )
            ),
            "Imported 1 reviewed tab and 1 password across 1 Space."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 2,
                    passwordCount: 2,
                    spaceCount: 2
                )
            ),
            "Imported 2 reviewed tabs and 2 passwords across 2 Spaces."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedManualSetup(
                    newSpaceCount: 2,
                    addedTabCount: 2
                )
            ),
            "Created 2 Spaces and added 2 tabs."
        )
    }

    private func makeFlow(
        entryPoint: BrowserOnboardingEntryPoint = .importBrowser,
        sourceDiscovery: any BrowserInstalledImportSourceDiscovering =
            StubSourceDiscovery(sources: []),
        dataAccessProvider: any BrowserOnboardingDataAccessProviding =
            StubDataAccessProvider(),
        reader: any BrowserOnboardingImportReading = ImmediateImportReader(
            result: .failure(TestFailure.read)
        ),
        importCommitter: any BrowserOnboardingImportCommitting =
            LiveBrowserOnboardingImportCommitter()
    ) -> BrowserOnboardingFlow {
        BrowserOnboardingFlow(
            request: BrowserOnboardingRequest(entryPoint: entryPoint),
            browser: BrowserStore(
                session: BrowserSession.preview,
                persistence: InMemoryBrowserSessionPersistence()
            ),
            sourceDiscovery: sourceDiscovery,
            dataAccessProvider: dataAccessProvider,
            importReader: reader,
            importCommitter: importCommitter
        )
    }

    private func source(
        _ application: BrowserImportApplication,
        hasDetectedData: Bool = true,
        detectedDataURL: URL? = nil
    ) -> BrowserInstalledImportSource {
        BrowserInstalledImportSource(
            application: application,
            applicationURL: URL(fileURLWithPath: "/Applications/\(application.name).app"),
            detectedPayload: BrowserDetectedImportPayload(
                application: application,
                profiles: [
                    BrowserDetectedImportProfile(
                        id: "Default",
                        name: "Default",
                        bookmarksURL: hasDetectedData
                            ? detectedDataURL
                                ?? URL(fileURLWithPath: #filePath)
                            : nil,
                        sessionURL: nil
                    )
                ]
            ),
            icon: NSImage(size: NSSize(width: 64, height: 64))
        )
    }

    private func makeSpace(name: String) -> BrowserSpace {
        let tab = BrowserTab(
            title: "Example",
            url: URL(string: "https://example.com"),
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "square.and.arrow.down",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func sessionAtSpaceLimit(
        from session: BrowserSession
    ) -> BrowserSession {
        var session = session
        while session.spaces.count < BrowserPortableArchive.maximumSpaceCount {
            session.spaces.append(
                makeSpace(name: "Existing \(session.spaces.count + 1)")
            )
        }
        session.repairRuntimeIntegrity()
        return session
    }

    private func portableImport(
        spaces: [BrowserSpace]
    ) -> BrowserPortableImport {
        BrowserPortableImport(
            spaces: spaces,
            summary: BrowserPortableImportSummary(
                spaceCount: spaces.count,
                folderCount: 0,
                liveTabCount: spaces.reduce(0) { $0 + $1.tabs.count },
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        )
    }

    private func readOutput(
        application: BrowserImportApplication,
        import portableImport: BrowserPortableImport
    ) -> BrowserOnboardingImportReadOutput {
        BrowserOnboardingImportReadOutput(
            payload: BrowserDetectedImportPayload(
                application: application,
                profiles: []
            ),
            imported: portableImport,
            passwordCandidates: []
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        predicate: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for onboarding flow state")
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

@MainActor
private struct StubSourceDiscovery: BrowserInstalledImportSourceDiscovering {
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}

@MainActor
private struct StubDataAccessProvider: BrowserOnboardingDataAccessProviding {
    func resolve(
        for application: BrowserImportApplication
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: BrowserImportApplication) {}

    func remember(
        _ directoryURL: URL,
        for application: BrowserImportApplication
    ) throws {}

    func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        completion(nil)
    }

    func hasSavedAccess(for application: BrowserImportApplication) -> Bool {
        false
    }
}

@MainActor
private final class SuspendedDataAccessProvider:
    BrowserOnboardingDataAccessProviding
{
    private var completion: (@MainActor (URL?) -> Void)?

    var hasPendingRequest: Bool { completion != nil }

    func resolve(
        for application: BrowserImportApplication
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: BrowserImportApplication) {}

    func remember(
        _ directoryURL: URL,
        for application: BrowserImportApplication
    ) throws {}

    func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        self.completion = completion
    }

    func hasSavedAccess(for application: BrowserImportApplication) -> Bool {
        false
    }

    func complete(with url: URL?) {
        let completion = completion
        self.completion = nil
        completion?(url)
    }
}

@MainActor
private final class SuspendedImportCommitter:
    BrowserOnboardingImportCommitting
{
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    func prepare(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> BrowserOnboardingPreparedImport {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
        try Task.checkCancellation()
        return BrowserOnboardingPreparedImport(passwords: [])
    }

    func finalize(
        plan: BrowserImportReviewPlan,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.commitReviewedImport(plan)
        return .empty
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class PostMutationSuspendedImportCommitter:
    BrowserOnboardingImportCommitting
{
    private var finalizationContinuation: CheckedContinuation<Void, Never>?
    private var finalizationStartWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> BrowserOnboardingPreparedImport {
        BrowserOnboardingPreparedImport(passwords: [])
    }

    func finalize(
        plan: BrowserImportReviewPlan,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.commitReviewedImport(plan)
        await withCheckedContinuation { continuation in
            finalizationContinuation = continuation
            for waiter in finalizationStartWaiters {
                waiter.resume()
            }
            finalizationStartWaiters.removeAll()
        }
        return .empty
    }

    func waitUntilFinalizationStarted() async {
        guard finalizationContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            finalizationStartWaiters.append(continuation)
        }
    }

    func completeFinalization() {
        finalizationContinuation?.resume()
        finalizationContinuation = nil
    }
}

private struct ImmediateImportReader: BrowserOnboardingImportReading {
    let result: Result<BrowserOnboardingImportReadOutput, TestFailure>

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        try result.get()
    }
}

private actor SequencedImportReader: BrowserOnboardingImportReading {
    private var results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]
    private(set) var readCount = 0

    init(results: [Result<BrowserOnboardingImportReadOutput, TestFailure>]) {
        self.results = results
    }

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        readCount += 1
        return try results.removeFirst().get()
    }
}

private actor SuspendedFlowImportReader: BrowserOnboardingImportReading {
    private var continuation:
        CheckedContinuation<
            BrowserOnboardingImportReadOutput,
            Error
        >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(_ output: BrowserOnboardingImportReadOutput) {
        continuation?.resume(returning: output)
        continuation = nil
    }
}

private enum TestFailure: LocalizedError {
    case read

    var errorDescription: String? { "The browser import could not be read." }
}
