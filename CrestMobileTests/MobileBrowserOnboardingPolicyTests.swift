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

    func testFirstRunAlwaysStartsAtWelcome() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.initialStep(for: .firstRun),
            .welcome
        )
    }

    func testDirectCustomizationStartsAtSpaceCustomization() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.initialStep(for: .manualSetup),
            .manualSetup
        )
    }

    func testExplicitRerunStartsAtWelcome() {
        XCTAssertEqual(MobileBrowserOnboardingPolicy.initialStep(for: .rerun), .welcome)
        XCTAssertNotEqual(BrowserOnboardingRequest.rerun, BrowserOnboardingRequest.rerun)
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

    func testImportRequestExplainsTheMacHandoff() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.initialStep(for: .importBrowser),
            .macImport
        )
    }

    func testFirstRunMovesDirectlyToSpaceSetup() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.nextStep(after: .welcome),
            .manualSetup
        )
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.nextStep(after: .featureSpaces),
            .featureTabs
        )
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.nextStep(after: .featureTabs),
            .featureSync
        )
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.nextStep(after: .featureSync),
            .manualSetup
        )
    }

    func testGuidedSetupFinishesAfterTheSingleSpaceEditor() {
        XCTAssertNil(MobileBrowserOnboardingPolicy.nextStep(after: .manualSetup))
    }
}
