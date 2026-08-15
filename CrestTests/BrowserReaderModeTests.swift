import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserReaderModeTests: XCTestCase {
    func testStatesKeepTheirExactToggleAndActivationPolicy() {
        let expectations: [(state: BrowserReaderModeState, canToggle: Bool, isActive: Bool)] = [
            (.unavailable, false, false),
            (.checking, false, false),
            (.available, true, false),
            (.activating, false, false),
            (.active, true, true),
        ]

        for expectation in expectations {
            XCTAssertEqual(expectation.state.canToggle, expectation.canToggle)
            XCTAssertEqual(expectation.state.isActive, expectation.isActive)
        }
    }

    func testActionsKeepTheirExactJavaScriptValues() {
        XCTAssertEqual(
            BrowserReaderModeAction.allCases.map(\.rawValue),
            ["availability", "activate", "deactivate", "snapshot"]
        )
    }

    func testSnapshotDecoderPreservesBridgeValues() throws {
        let snapshot = try BrowserReaderModeSnapshotDecoder.decode([
            "isActive": true,
            "title": "An Article",
            "text": "Readable text",
            "unsafeElementCount": NSNumber(value: 3),
        ])

        XCTAssertEqual(
            snapshot,
            BrowserReaderModeSnapshot(
                isActive: true,
                title: "An Article",
                text: "Readable text",
                unsafeElementCount: 3
            )
        )
    }

    func testSnapshotDecoderKeepsMissingBridgeValueDefaults() throws {
        XCTAssertEqual(
            try BrowserReaderModeSnapshotDecoder.decode([:]),
            BrowserReaderModeSnapshot(
                isActive: false,
                title: "",
                text: "",
                unsafeElementCount: 0
            )
        )
    }

    func testSnapshotDecoderRejectsANonObjectBridgeValue() {
        XCTAssertThrowsError(
            try BrowserReaderModeSnapshotDecoder.decode("not a snapshot")
        ) { error in
            XCTAssertEqual(error as? BrowserReaderModeError, .presentationFailed)
        }
    }

    func testErrorsKeepTheirLocalizedDescriptions() {
        XCTAssertEqual(
            BrowserReaderModeError.articleUnavailable.errorDescription,
            "Reader Mode is not available for this page."
        )
        XCTAssertEqual(
            BrowserReaderModeError.presentationFailed.errorDescription,
            "This page could not be presented in Reader Mode."
        )
    }

    func testPresentationCopyResolvesInEnglishAndArabic() {
        let expectations: [(resource: LocalizedStringResource, english: String, arabic: String)] = [
            (
                BrowserReaderModePresentation.accessibilityLabel,
                "Reader Mode",
                "وضع القارئ"
            ),
            (
                BrowserReaderModePresentation.articleUnavailableDescription,
                "Reader Mode is not available for this page.",
                "وضع القارئ غير متاح لهذه الصفحة."
            ),
            (
                BrowserReaderModePresentation.presentationFailedDescription,
                "This page could not be presented in Reader Mode.",
                "تعذّر عرض هذه الصفحة في وضع القارئ."
            ),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "en"),
                expectation.english
            )
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "ar"),
                expectation.arabic
            )
        }
    }

    @MainActor
    func testContentWorldNameRemainsStable() {
        XCTAssertEqual(
            BrowserReaderModeController.contentWorld.name,
            "Crest.ReaderMode"
        )
    }

    private func localized(
        _ resource: LocalizedStringResource,
        localeIdentifier: String
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = Locale(identifier: localeIdentifier)
        return String(localized: localizedResource)
    }
}
