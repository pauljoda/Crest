import XCTest
@testable import Crest

final class BrowserOnboardingProgressTests: XCTestCase {
    @MainActor
    func testOrdinaryIsolatedLaunchDoesNotOpenLiveOnboardingDiscovery() {
        let progress = BrowserOnboardingProgressStore.launchStore(
            isIsolated: true,
            forceWelcome: false,
            forceSetup: false
        )

        XCTAssertFalse(progress.shouldPresentWelcome)
        XCTAssertTrue(progress.hasCompletedSetup)
    }

    @MainActor
    func testForcedIsolatedOnboardingStillPresentsTheFixtureFlow() {
        let progress = BrowserOnboardingProgressStore.launchStore(
            isIsolated: true,
            forceWelcome: true,
            forceSetup: true
        )

        XCTAssertTrue(progress.shouldPresentWelcome)
        XCTAssertFalse(progress.hasCompletedSetup)
    }

    @MainActor
    func testWelcomePresentationDependsOnThisInstallNotTheCloudResult() throws {
        let suite = "BrowserOnboardingProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let freshInstall = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertTrue(freshInstall.shouldPresentWelcome)

        defaults.set(true, forKey: BrowserOnboardingProgressStore.completionKey)
        let returningInstall = BrowserOnboardingProgressStore(defaults: defaults)
        XCTAssertFalse(returningInstall.shouldPresentWelcome)

        let forced = BrowserOnboardingProgressStore(
            defaults: defaults,
            forceWelcome: true
        )
        XCTAssertTrue(forced.shouldPresentWelcome)
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

    func testWelcomeWaitsForBothICloudChecksBeforeOfferingAnAction() {
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: true,
                cloudPhase: .ready,
                hasCompletedSetup: false
            ),
            .checking
        )
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: false,
                cloudPhase: .checking,
                hasCompletedSetup: false
            ),
            .checking
        )
    }

    func testWelcomeOpensWhenSetupCompletedOnThisInstall() {
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: false,
                cloudPhase: .ready,
                hasCompletedSetup: true
            ),
            .open
        )
    }

    func testWelcomeStillOffersSetupWhenThisInstallIsIncomplete() {
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: false,
                cloudPhase: .ready,
                hasCompletedSetup: false
            ),
            .setup
        )
    }

    func testWelcomeOffersSetupForTheDisposableSeedSession() {
        XCTAssertEqual(
            BrowserOnboardingWelcomePolicy.action(
                progressIsChecking: false,
                cloudPhase: .ready,
                hasCompletedSetup: false
            ),
            .setup
        )
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

    @MainActor
    func testForcedWelcomeKeepsTheLaunchGateActiveAfterRefresh() async throws {
        let suite = "BrowserOnboardingProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BrowserOnboardingProgressStore.completionKey)

        let progress = BrowserOnboardingProgressStore(
            defaults: defaults,
            forceWelcome: true
        )
        await progress.refresh()

        XCTAssertTrue(progress.isLaunchGateActive)
        XCTAssertFalse(progress.isChecking)
        XCTAssertTrue(progress.hasCompletedSetup)
    }
}
