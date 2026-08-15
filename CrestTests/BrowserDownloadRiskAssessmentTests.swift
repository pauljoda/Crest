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

    func testDirectionChangingFilenameIsSanitizedAndRequiresConfirmation() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "photo.jpg\u{202E}gpj.command",
            mimeType: "application/octet-stream"
        )

        XCTAssertFalse(assessment.sanitizedFilename.contains("\u{202E}"))
        XCTAssertTrue(assessment.reasons.contains(.deceptiveFilename))
        XCTAssertTrue(assessment.reasons.contains(.executableOrInstaller))
    }

    func testDangerousMIMEAndBenignExtensionMismatchIsExplicit() {
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "holiday.jpg",
            mimeType: "application/x-mach-binary"
        )

        XCTAssertTrue(assessment.reasons.contains(.executableOrInstaller))
        XCTAssertTrue(assessment.reasons.contains(.dangerousTypeMismatch))
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

    func testRiskReasonPresentationResolvesEnglishAndArabicWarningCopy() {
        let expectations: [(BrowserDownloadRiskReason, String, String)] = [
            (
                .executableOrInstaller,
                "This file type can install or run software.",
                "يمكن لهذا النوع من الملفات تثبيت البرامج أو تشغيلها."
            ),
            (
                .deceptiveFilename,
                "The original filename used invisible or direction-changing characters that can disguise its real extension.",
                "استخدم اسم الملف الأصلي أحرفًا غير مرئية أو أحرفًا تغيّر اتجاه النص لإخفاء امتداده الحقيقي."
            ),
            (
                .dangerousTypeMismatch,
                "The server-reported file type does not match the filename and one of those types can run software.",
                "نوع الملف الذي أبلغ عنه الخادم لا يطابق اسم الملف، ويمكن لأحد هذين النوعين تشغيل البرامج."
            ),
        ]

        for (reason, expectedEnglish, expectedArabic) in expectations {
            var englishResource = reason.warningMessage
            englishResource.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: englishResource), expectedEnglish)

            var arabicResource = reason.warningMessage
            arabicResource.locale = Locale(identifier: "ar")
            XCTAssertEqual(String(localized: arabicResource), expectedArabic)
        }
    }
}
