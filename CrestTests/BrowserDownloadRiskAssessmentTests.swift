import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadRiskAssessmentTests: XCTestCase {
    func testOrdinaryDocumentDoesNotRequireConfirmation() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "report.pdf",
            mimeType: "application/pdf"
        )

        XCTAssertEqual(assessment.sanitizedFilename, "report.pdf")
        XCTAssertFalse(assessment.requiresConfirmation)
        XCTAssertTrue(assessment.reasons.isEmpty)
    }

    func testExecutableInstallerAndScriptExtensionsRequireConfirmation() {
        for filename in ["update.pkg", "tool.command", "setup.EXE", "profile.mobileconfig"] {
            let assessment = BrowserDownloadRiskAssessment.assess(
                suggestedFilename: filename,
                mimeType: "application/octet-stream"
            )

            XCTAssertTrue(assessment.requiresConfirmation, filename)
            XCTAssertTrue(assessment.reasons.contains(.executableOrInstaller), filename)
        }
    }

    func testUserInitiatedInstallerUsesThePlatformDownloadProtection() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "Crest.dmg",
            mimeType: "application/x-apple-diskimage"
        )

        XCTAssertFalse(assessment.requiresConfirmation(isUserInitiated: true))
        XCTAssertTrue(assessment.requiresConfirmation(isUserInitiated: false))
    }

    func testDirectionChangingFilenameIsSanitizedAndRequiresConfirmation() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "photo.jpg\u{202E}gpj.command",
            mimeType: "application/octet-stream"
        )

        XCTAssertFalse(assessment.sanitizedFilename.contains("\u{202E}"))
        XCTAssertTrue(assessment.reasons.contains(.deceptiveFilename))
        XCTAssertTrue(assessment.reasons.contains(.executableOrInstaller))
        XCTAssertTrue(assessment.requiresConfirmation(isUserInitiated: true))
    }

    func testDangerousMIMEAndBenignExtensionMismatchIsExplicit() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "holiday.jpg",
            mimeType: "application/x-mach-binary"
        )

        XCTAssertTrue(assessment.reasons.contains(.executableOrInstaller))
        XCTAssertTrue(assessment.reasons.contains(.dangerousTypeMismatch))
        XCTAssertTrue(assessment.requiresConfirmation(isUserInitiated: true))
    }

    func testPathTraversalIsNeutralizedWithoutMakingTheSafeResultDangerous() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "../../notes.txt",
            mimeType: "text/plain"
        )

        XCTAssertEqual(assessment.sanitizedFilename, "notes.txt")
        XCTAssertFalse(assessment.requiresConfirmation)
    }

    func testRiskAssessmentCodingPreservesKeysAndReasonRawValues() throws {
        let assessment = BrowserDownloadRiskAssessment(
            sanitizedFilename: "update.pkg",
            reasons: [.executableOrInstaller, .dangerousTypeMismatch]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(assessment)

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"reasons":["executableOrInstaller","dangerousTypeMismatch"],"sanitizedFilename":"update.pkg"}"#
        )
        XCTAssertEqual(
            try JSONDecoder().decode(BrowserDownloadRiskAssessment.self, from: data),
            assessment
        )
    }

}
