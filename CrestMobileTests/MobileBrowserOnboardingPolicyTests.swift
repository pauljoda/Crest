import XCTest

@testable import CrestMobile

final class MobileBrowserOnboardingPolicyTests: XCTestCase {
    func testAutomaticWelcomeIsSuppressedForAnIsolatedTestLaunch() {
        XCTAssertFalse(
            MobileBrowserAutomaticOnboardingPolicy.shouldPresent(
                forceOnboarding: false,
                usesIsolatedLaunch: true
            )
        )
    }

    func testExplicitOnboardingFixtureOverridesLaunchIsolation() {
        XCTAssertTrue(
            MobileBrowserAutomaticOnboardingPolicy.shouldPresent(
                forceOnboarding: true,
                usesIsolatedLaunch: true
            )
        )
    }

    func testProductionLaunchCanPresentTheAutomaticWelcome() {
        XCTAssertTrue(
            MobileBrowserAutomaticOnboardingPolicy.shouldPresent(
                forceOnboarding: false,
                usesIsolatedLaunch: false
            )
        )
    }

    func testLaunchGateOnlyReplacesTheBrowserOnAnIncompleteInstall() {
        XCTAssertTrue(
            MobileBrowserAutomaticOnboardingPolicy.showsLaunchGate(
                automaticallyPresentsOnboarding: true,
                isLaunchGateActive: true
            )
        )
        XCTAssertFalse(
            MobileBrowserAutomaticOnboardingPolicy.showsLaunchGate(
                automaticallyPresentsOnboarding: true,
                isLaunchGateActive: false
            )
        )
        XCTAssertFalse(
            MobileBrowserAutomaticOnboardingPolicy.showsLaunchGate(
                automaticallyPresentsOnboarding: false,
                isLaunchGateActive: true
            )
        )
    }

    @MainActor
    func testRerunDiscardsTheOldDraftAndKeepsExistingSpaces() throws {
        let session = BrowserSession.preview
        var oldDraft = BrowserManualSetupPlan(existing: session)
        let uncommittedID = try oldDraft.addSpace()
        let persistence = MobileOnboardingDraftPersistence(load: { oldDraft }, save: { _ in }, clear: {})
        let resumed = persistence.plan(for: .firstRun, existing: session)
        XCTAssertTrue(resumed.spaces.contains { $0.id == uncommittedID })
        let rerun = persistence.plan(for: .rerun, existing: session)
        XCTAssertEqual(rerun, BrowserManualSetupPlan(existing: session))
        XCTAssertFalse(rerun.spaces.contains { $0.id == uncommittedID })
    }

}
