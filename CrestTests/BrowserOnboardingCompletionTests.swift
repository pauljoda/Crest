import XCTest

@testable import Crest

@MainActor
final class BrowserOnboardingCompletionTests: XCTestCase {
    func testCompletionUsesFirstOrderedSpaceAndReplayReusesItsGuideBeforeRetiringTheGate() async throws {
        let browser = BrowserStore.preview()
        let first = try XCTUnwrap(browser.session.spaces.first)
        browser.selectSpace(try XCTUnwrap(browser.session.spaces.last?.id))
        let originalTabs = first.tabs
        let progress = BrowserOnboardingProgressStore(persistence: InMemoryBrowserOnboardingProgressPersistence())
        let access = BrowserSpaceAccessController()
        var opened: BrowserTabRuntimeAssignment?
        let result = await BrowserOnboardingCompletion.complete(
            request: .firstRun, browser: browser, progress: progress, spaceAccess: access,
            willComplete: { guide in
                XCTAssertTrue(progress.isLaunchGateActive)
                XCTAssertFalse(progress.hasCompletedSetup)
                opened = guide
            })
        let guide = try XCTUnwrap(opened)
        XCTAssertEqual(result, .completed(guide: guide))
        XCTAssertEqual(guide.spaceID, first.id)
        XCTAssertEqual(guide.profileID, first.profile.id)
        XCTAssertEqual(browser.selectedTab?.id, guide.tabID)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent != .gettingStarted }, originalTabs)
        let replay = await BrowserOnboardingCompletion.complete(
            request: .rerun, browser: browser, progress: progress, spaceAccess: access)
        XCTAssertEqual(replay, .completed(guide: guide))
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent == .gettingStarted }.count, 1)
    }

    func testDeniedAuthenticationLeavesManualPlanUncommittedAndRetryAddsEachSpaceOnce() async throws {
        let browser = protectedBrowser()
        var plan = BrowserManualSetupPlan(existing: browser.session)
        let addedID = try plan.addSpace()
        let authenticator = OnboardingCompletionAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let persistence = InMemoryBrowserOnboardingProgressPersistence()
        let progress = BrowserOnboardingProgressStore(persistence: persistence)
        let before = browser.session
        let rejected = Task {
            await BrowserOnboardingCompletion.complete(
                request: .firstRun, browser: browser, progress: progress, spaceAccess: access, manualPlan: plan)
        }
        await authenticator.waitForRequest()
        authenticator.resolve(false)
        let rejection = await rejected.value
        XCTAssertEqual(rejection, .cancelled)
        XCTAssertEqual(browser.session, before)
        XCTAssertFalse(persistence.hasCompletedSetup)

        let retry = Task {
            await BrowserOnboardingCompletion.complete(
                request: .firstRun, browser: browser, progress: progress, spaceAccess: access, manualPlan: plan)
        }
        await authenticator.waitForRequest()
        authenticator.resolve(true)
        guard case .completed(let guide) = await retry.value else { return XCTFail("Setup did not complete") }
        XCTAssertEqual(guide?.spaceID, before.spaces.first?.id)
        XCTAssertEqual(browser.session.spaces.filter { $0.id == addedID }.count, 1)
        XCTAssertTrue(persistence.hasCompletedSetup)
    }

    func testCancelledTaskAndChangedFirstSpaceCannotCommitAfterAuthentication() async throws {
        enum Interruption: CaseIterable { case cancellation, reorder, profile, removal }
        for interruption in Interruption.allCases {
            let browser = protectedBrowser()
            let authenticator = OnboardingCompletionAuthenticator()
            let access = BrowserSpaceAccessController(authenticator: authenticator)
            let progress = BrowserOnboardingProgressStore(persistence: InMemoryBrowserOnboardingProgressPersistence())
            let task = Task {
                await BrowserOnboardingCompletion.complete(
                    request: .firstRun, browser: browser, progress: progress, spaceAccess: access)
            }
            await authenticator.waitForRequest()
            switch interruption {
            case .cancellation: task.cancel()
            case .reorder: browser.moveSpaces(from: IndexSet(integer: 0), to: browser.session.spaces.count)
            case .profile:
                let first = try XCTUnwrap(browser.session.spaces.first)
                browser.session.spaces[0] = BrowserSpace(
                    id: first.id, profile: BrowsingProfile(), name: first.name, symbol: first.symbol,
                    accent: first.accent, folders: first.folders, tabs: first.tabs,
                    accessPolicy: first.accessPolicy, selectedTabID: first.selectedTabID)
            case .removal: browser.session.spaces.removeFirst()
            }
            let beforeResolution = browser.session
            authenticator.resolve(true)
            let result = await task.value
            XCTAssertEqual(result, interruption == .cancellation ? .cancelled : .sourceChanged)
            XCTAssertEqual(browser.session, beforeResolution)
            XCTAssertFalse(progress.hasCompletedSetup)
        }
    }

    func testManualCompletionPreservesUnrelatedUpdatesDuringAuthentication() async throws {
        let browser = protectedBrowser()
        var plan = BrowserManualSetupPlan(existing: browser.session)
        let addedID = try plan.addSpace()
        let authenticator = OnboardingCompletionAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let progress = BrowserOnboardingProgressStore(persistence: InMemoryBrowserOnboardingProgressPersistence())
        let task = Task {
            await BrowserOnboardingCompletion.complete(
                request: .firstRun, browser: browser, progress: progress, spaceAccess: access, manualPlan: plan)
        }
        await authenticator.waitForRequest()
        browser.session.spaces[1].tabs[0].title = "Updated during setup"
        authenticator.resolve(true)
        guard case .completed = await task.value else { return XCTFail("Setup did not complete") }
        XCTAssertEqual(browser.session.spaces[1].tabs[0].title, "Updated during setup")
        XCTAssertEqual(browser.session.spaces.filter { $0.id == addedID }.count, 1)
    }

    func testPrivateStoreCannotConsumeNormalSetupCompletion() async {
        let browser = BrowserStore.privateBrowsing()
        let before = browser.session
        let progress = BrowserOnboardingProgressStore(persistence: InMemoryBrowserOnboardingProgressPersistence())
        let result = await BrowserOnboardingCompletion.complete(
            request: .rerun, browser: browser, progress: progress, spaceAccess: BrowserSpaceAccessController())
        XCTAssertEqual(result, .sourceChanged)
        XCTAssertEqual(browser.session, before)
        XCTAssertFalse(progress.hasCompletedSetup)
    }

    private func protectedBrowser() -> BrowserStore {
        var session = BrowserSession.preview
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        return BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
    }
}

@MainActor
private final class OnboardingCompletionAuthenticator: BrowserDeviceAuthenticating {
    private var request: CheckedContinuation<Bool, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func authenticate(reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            request = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resolve(_ allowed: Bool) {
        let pending = request
        request = nil
        pending?.resume(returning: allowed)
    }
}
