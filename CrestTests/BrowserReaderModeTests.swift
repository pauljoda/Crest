import Foundation
import XCTest

@testable import Crest

final class BrowserReaderModeTests: XCTestCase {

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
}
