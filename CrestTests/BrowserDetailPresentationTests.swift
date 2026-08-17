import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDetailPresentationTests: XCTestCase {
    func testChromeInstallPhasePreservesPresentationPriority() {
        let candidate = BrowserDetailPresentationTestFixture.chromeCandidate

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
        let saveCandidate = BrowserDetailPresentationTestFixture.credentialSaveCandidate
        let currentRequest = BrowserDetailPresentationTestFixture.currentCredentialRequest
        let newRequest = BrowserDetailPresentationTestFixture.newCredentialRequest

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

@MainActor
private enum BrowserDetailPresentationTestFixture {
    static let chromeCandidate: BrowserChromeWebStoreCandidate = {
        guard
            let url = URL(
                string:
                    "https://chromewebstore.google.com/detail/reading-focus/abcdefghijklmnopabcdefghijklmnop"
            ),
            let item = BrowserChromeWebStoreItem(url: url)
        else {
            preconditionFailure("The Chrome Web Store test URL is invalid.")
        }
        let source = BrowserChromeWebStoreSource(
            extensionID: item.id,
            storeURL: item.storeURL,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: String(repeating: "b", count: 64)
        )
        return BrowserChromeWebStoreCandidate(
            item: item,
            source: source,
            verifiedPackage: BrowserVerifiedCRX3Package(
                extensionID: item.id,
                crxData: Data(),
                zipArchiveData: Data(),
                crxSHA256Hex: source.crxSHA256Hex,
                publisherKeyHashHex: source.publisherKeyHashHex
            ),
            displayName: "Reading Focus",
            version: "1.0.0",
            displayDescription: "A verified extension.",
            requestedPermissions: ["storage"],
            requestedHosts: [],
            errors: [],
            iconPayload: nil,
            hasOptionsPage: false,
            hasCommands: false,
            hasContentModificationRules: false,
            nativeMessagingCapability: .available,
            iCloudPasswordsCapability: .available
        )
    }()

    static let currentCredentialRequest = BrowserCredentialFillRequest(
        id: uuid(0x41),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        usernameHint: "reader@example.com",
        passwordKind: .current,
        isCrossOriginFrame: false,
        requestedAt: fixedDate
    )

    static let newCredentialRequest = BrowserCredentialFillRequest(
        id: uuid(0x42),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        usernameHint: "reader@example.com",
        passwordKind: .new,
        isCrossOriginFrame: false,
        requestedAt: fixedDate
    )

    static let credentialSaveCandidate = BrowserCredentialSaveCandidate(
        id: uuid(0x43),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        username: "reader@example.com",
        password: "test-password",
        passwordKind: .current,
        isCrossOriginFrame: false,
        submittedAt: fixedDate
    )

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let credentialOrigin: CredentialOrigin = {
        guard
            let url = URL(string: "https://accounts.test.example"),
            let origin = CredentialOrigin(url: url)
        else {
            preconditionFailure("The credential test origin is invalid.")
        }
        return origin
    }()

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x54,
                0x45, 0x53,
                0x54, 0x44,
                0x45, 0x54, 0x41, 0x49, 0x4C, finalByte
            ))
    }
}
