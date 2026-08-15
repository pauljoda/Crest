import XCTest

@testable import Crest

@MainActor
final class BrowserDetailPresentationTests: XCTestCase {
    func testChromeInstallPhasePreservesPresentationPriority() {
        let candidate = BrowserChromeWebStoreInstallPreviewFixture.candidate

        let preparing = BrowserChromeWebStoreInstallPhase.resolve(
            isPreparing: true,
            installedName: "Installed",
            candidate: candidate,
            errorDescription: "Failed"
        )
        guard case .preparing = preparing else {
            return XCTFail("Preparation must remain the highest-priority state.")
        }

        let installed = BrowserChromeWebStoreInstallPhase.resolve(
            isPreparing: false,
            installedName: "Installed",
            candidate: candidate,
            errorDescription: "Failed"
        )
        guard case .installed("Installed") = installed else {
            return XCTFail("Installed content must precede retained review state.")
        }

        let review = BrowserChromeWebStoreInstallPhase.resolve(
            isPreparing: false,
            installedName: nil,
            candidate: candidate,
            errorDescription: "Failed"
        )
        guard case .review(let resolvedCandidate, let errorDescription) = review else {
            return XCTFail("A prepared candidate must remain reviewable.")
        }
        XCTAssertEqual(resolvedCandidate.id, candidate.id)
        XCTAssertEqual(errorDescription, "Failed")

        let failed = BrowserChromeWebStoreInstallPhase.resolve(
            isPreparing: false,
            installedName: nil,
            candidate: nil,
            errorDescription: "Failed"
        )
        guard case .failed("Failed") = failed else {
            return XCTFail("An error without a candidate must show failure content.")
        }
    }

    func testCredentialChromePreservesSaveThenPasswordKindRouting() {
        let saveCandidate = BrowserCredentialChromePreviewFixture.credentialSaveCandidate
        let currentRequest = BrowserCredentialChromePreviewFixture.currentCredentialRequest
        let newRequest = BrowserCredentialChromePreviewFixture.newCredentialRequest

        XCTAssertEqual(
            BrowserCredentialChromePresentation.resolve(
                saveCandidate: saveCandidate,
                fillRequest: newRequest
            ),
            .save(saveCandidate)
        )
        XCTAssertEqual(
            BrowserCredentialChromePresentation.resolve(
                saveCandidate: nil,
                fillRequest: newRequest
            ),
            .strongPassword(newRequest)
        )
        XCTAssertEqual(
            BrowserCredentialChromePresentation.resolve(
                saveCandidate: nil,
                fillRequest: currentRequest
            ),
            .suggestions(currentRequest)
        )
        XCTAssertEqual(
            BrowserCredentialChromePresentation.resolve(
                saveCandidate: nil,
                fillRequest: nil
            ),
            .none
        )
    }
}
