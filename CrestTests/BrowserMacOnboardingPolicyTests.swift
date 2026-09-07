import XCTest

@testable import Crest

final class BrowserMacOnboardingPolicyTests: XCTestCase {
    func testFirstRunMovesDirectlyToOptionalImport() {
        XCTAssertEqual(
            BrowserMacOnboardingPolicy.nextFirstRunStep(after: .welcome),
            .importBrowser
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

    func testFirstRunImportContinuesToSpaceCustomization() {
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
