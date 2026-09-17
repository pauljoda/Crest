import XCTest

@testable import Crest

final class BrowserOnboardingProgressTests: XCTestCase {

    @MainActor
    func testGettingStartedIsConsumedOnceForThisInstall() throws {
        let suite = "BrowserOnboardingProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertTrue(first.completeSetup(for: .firstRun))
        XCTAssertFalse(first.completeSetup(for: .firstRun))
        let relaunched = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(relaunched.shouldPresentWelcome)
        XCTAssertFalse(relaunched.completeSetup(for: .firstRun))
        let forced = BrowserOnboardingProgressStore(defaults: defaults, forceWelcome: true, forceSetup: true)
        XCTAssertFalse(forced.hasCompletedSetup)
        XCTAssertFalse(forced.completeSetup(for: .firstRun))
    }

    @MainActor
    func testRerunStartsSetupAndReopensGuideWithoutResettingInstallCompletion() {
        let persistence = InMemoryBrowserOnboardingProgressPersistence(hasCompletedSetup: true)
        let progress = BrowserOnboardingProgressStore(persistence: persistence)
        XCTAssertFalse(progress.shouldPresentWelcome)
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: false, cloudPhase: .ready, hasCompletedSetup: progress.hasCompletedSetup,
                entryPoint: .rerun), .setup)
        XCTAssertTrue(progress.willOpenGettingStarted(for: .rerun))
        XCTAssertTrue(progress.completeSetup(for: .rerun))
        XCTAssertTrue(persistence.hasCompletedSetup)
        XCTAssertFalse(progress.shouldPresentWelcome)
    }

    @MainActor
    func testNamedIsolatedInstallKeepsCompletionAcrossLaunches() throws {
        let id = "onboarding-test-\(UUID().uuidString)"
        let suite = BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BrowserOnboardingProgressStore.launchStore(
            isIsolated: true, forceWelcome: true, forceSetup: false, persistentIsolationID: id)
        XCTAssertTrue(first.completeSetup(for: .firstRun))
        let next = BrowserOnboardingProgressStore.launchStore(
            isIsolated: true, forceWelcome: false, forceSetup: false, persistentIsolationID: id)
        XCTAssertFalse(next.shouldPresentWelcome)
        XCTAssertFalse(next.completeSetup(for: .firstRun))
    }

    @MainActor
    func testCompletingSetupUnlocksThisInstallWithoutAnotherCloudCheck() throws {
        let suite = "BrowserOnboardingProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstLaunch = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertTrue(firstLaunch.isLaunchGateActive)
        XCTAssertTrue(firstLaunch.isChecking)

        firstLaunch.markCompleted()

        XCTAssertFalse(firstLaunch.isLaunchGateActive)
        XCTAssertFalse(firstLaunch.isChecking)

        let nextLaunch = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(nextLaunch.isLaunchGateActive)
        XCTAssertFalse(nextLaunch.isChecking)
        XCTAssertTrue(nextLaunch.hasCompletedSetup)
    }

    @MainActor
    func testForcedSetupIgnoresAStoredCompletionDuringFixtureRefresh() async throws {
        let suite = "BrowserOnboardingProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BrowserOnboardingProgressStore.completionKey)

        let progress = BrowserOnboardingProgressStore(
            defaults: defaults,
            forceWelcome: true,
            forceSetup: true
        )
        await progress.refresh()

        XCTAssertFalse(progress.isChecking)
        XCTAssertFalse(progress.hasCompletedSetup)
    }

}
