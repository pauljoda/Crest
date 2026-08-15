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

    func testSettingsReplayStartsAtTheFeatureTour() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.initialStep(for: .manualSetup),
            .featureSpaces
        )
    }

    func testImportRequestExplainsTheMacHandoff() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.initialStep(for: .importBrowser),
            .macImport
        )
    }

    func testFirstRunTeachesCoreFeaturesBeforeSpaceSetup() {
        XCTAssertEqual(
            MobileBrowserOnboardingPolicy.nextStep(after: .welcome),
            .featureSpaces
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
