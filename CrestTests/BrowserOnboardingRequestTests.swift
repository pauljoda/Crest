import XCTest
@testable import Crest

final class BrowserOnboardingRequestTests: XCTestCase {
    func testRepeatedPresentationRequestsAreDistinct() {
        XCTAssertNotEqual(
            BrowserOnboardingRequest.importBrowser,
            BrowserOnboardingRequest.importBrowser
        )
        XCTAssertNotEqual(
            BrowserOnboardingRequest.manualSetup,
            BrowserOnboardingRequest.manualSetup
        )
    }
}
