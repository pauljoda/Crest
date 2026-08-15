import XCTest
@testable import Crest

final class BrowserMacOnboardingPolicyTests: XCTestCase {
    func testFirstRunTeachesCoreFeaturesBeforeOptionalImport() {
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .welcome),
            .featureSpaces
        )
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .featureSpaces),
            .featureTabs
        )
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .featureTabs),
            .featureSync
        )
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .featureSync),
            .importBrowser
        )
    }

    func testImportAndSpaceSetupRemainExplicitWizardSteps() {
        XCTAssertNil(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .importBrowser)
        )
        XCTAssertNil(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .manualSetup)
        )
    }

    func testFirstRunImportContinuesToMandatorySpaceSetup() {
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.destinationAfterImport(for: .firstRun),
            .manualSetup
        )
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.destinationAfterImport(for: .importBrowser),
            .complete
        )
    }
}
