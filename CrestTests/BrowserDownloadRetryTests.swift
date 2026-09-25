import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadRetryTests: XCTestCase {
    func testAutomaticDownloadRetryBuildsAFreshReplayableNetworkRequest() throws {
        let url = try XCTUnwrap(URL(string: "https://downloads.example/report"))
        let documentURL = try XCTUnwrap(URL(string: "https://downloads.example/page"))
        var original = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 42
        )
        original.httpMethod = "POST"
        original.setValue("application/json", forHTTPHeaderField: "Content-Type")
        original.httpBody = Data(#"{"scope":"fixture"}"#.utf8)
        original.mainDocumentURL = documentURL
        original.httpShouldHandleCookies = false
        original.networkServiceType = .responsiveData
        original.allowsCellularAccess = false

        let replay = try XCTUnwrap(
            BrowserDownloadRetryRequestPolicy.replayableRequest(from: original)
        )

        XCTAssertEqual(replay.url, url)
        XCTAssertEqual(replay.cachePolicy, original.cachePolicy)
        XCTAssertEqual(replay.timeoutInterval, 42)
        XCTAssertEqual(replay.httpMethod, "POST")
        XCTAssertEqual(replay.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(replay.httpBody, original.httpBody)
        XCTAssertEqual(replay.mainDocumentURL, documentURL)
        XCTAssertFalse(replay.httpShouldHandleCookies)
        XCTAssertEqual(replay.networkServiceType, .responsiveData)
        XCTAssertFalse(replay.allowsCellularAccess)
    }

    func testAutomaticDownloadRetryRejectsOneShotAndNonNetworkRequests() throws {
        let url = try XCTUnwrap(URL(string: "https://downloads.example/report"))
        var streamRequest = URLRequest(url: url)
        streamRequest.httpBodyStream = InputStream(data: Data("fixture".utf8))
        let fileRequest = URLRequest(
            url: URL(fileURLWithPath: "/tmp/crest-download-fixture")
        )

        XCTAssertNil(
            BrowserDownloadRetryRequestPolicy.replayableRequest(from: streamRequest)
        )
        XCTAssertNil(
            BrowserDownloadRetryRequestPolicy.replayableRequest(from: fileRequest)
        )
    }

    func testRetryRegistrationRequiresTheExactLiveLeaseContextAndLedgerItem() {
        let leaseID = fixedID(0x11)
        let itemID = fixedID(0x12)
        let profileID = fixedID(0x13)
        let spaceID = fixedID(0x14)
        let lease = BrowserDownloadRetryLease(
            id: leaseID,
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID
        )
        let item = DownloadState.fixture(
            id: itemID, profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: 1_000))

        XCTAssertTrue(
            BrowserDownloadRetryRegistrationPolicy.shouldRegister(
                lease: lease,
                currentLease: lease,
                item: item,
                contextAssignment: lease.assignment,
                isAssignmentAvailable: true
            )
        )
    }

    func testRetryRegistrationRejectsDeletedReplacedAndStaleState() {
        let itemID = fixedID(0x21)
        let profileID = fixedID(0x22)
        let spaceID = fixedID(0x23)
        let lease = BrowserDownloadRetryLease(
            id: fixedID(0x24),
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID
        )
        let createdAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let item = DownloadState.fixture(id: itemID, profileID: profileID, createdAt: createdAt)
        let replacedLease = BrowserDownloadRetryLease(
            id: fixedID(0x25),
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID
        )
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: fixedID(0x26)
        )
        let completedItem = DownloadState.fixture(
            id: itemID, profileID: profileID, createdAt: createdAt, phase: .finished)
        let canceledItem = DownloadState.fixture(
            id: itemID, profileID: profileID, createdAt: createdAt, phase: .canceled, message: "Canceled.")

        let rejectedInputs:
            [(
                BrowserDownloadRetryLease?, DownloadState?, BrowserSpaceRuntimeAssignment?, Bool
            )] = [
                (nil, item, lease.assignment, true),
                (replacedLease, item, lease.assignment, true),
                (lease, nil, lease.assignment, true),
                (lease, item, nil, true),
                (lease, item, replacementAssignment, true),
                (lease, completedItem, lease.assignment, true),
                (lease, canceledItem, lease.assignment, true),
                (lease, item, lease.assignment, false),
            ]
        for (currentLease, currentItem, contextAssignment, isAssignmentAvailable) in rejectedInputs {
            XCTAssertFalse(
                BrowserDownloadRetryRegistrationPolicy.shouldRegister(
                    lease: lease,
                    currentLease: currentLease,
                    item: currentItem,
                    contextAssignment: contextAssignment,
                    isAssignmentAvailable: isAssignmentAvailable
                )
            )
        }
    }

    func testDownloadSourceCaptureIsClampedMatchedOnceAndExpires() throws {
        let destination = try XCTUnwrap(URL(string: "https://example.com/file.bin"))
        let capture = BrowserDownloadSourceCapture(
            destinationURL: destination,
            normalizedSourceRect: CGRect(x: -1, y: 0.8, width: 2, height: 1),
            normalizedTouchPoint: CGPoint(x: 1.4, y: -0.2)
        )
        XCTAssertEqual(capture.normalizedSourceRect.minX, 0, accuracy: 0.000_001)
        XCTAssertEqual(capture.normalizedSourceRect.minY, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(capture.normalizedSourceRect.width, 1, accuracy: 0.000_001)
        XCTAssertEqual(capture.normalizedSourceRect.height, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(capture.normalizedTouchPoint, CGPoint(x: 1, y: 0))

        var store = BrowserDownloadSourceStore(maximumAge: 2)
        store.record(capture, uptime: 10)
        XCTAssertNil(
            store.consume(
                destinationURL: URL(string: "https://example.com/other.bin"),
                uptime: 11
            )
        )
        XCTAssertEqual(store.consume(destinationURL: destination, uptime: 11), capture)
        store.record(capture, uptime: 20)
        XCTAssertNil(store.consume(destinationURL: destination, uptime: 23))
        store.record(capture, uptime: 30)
        XCTAssertEqual(store.consume(destinationURL: destination, uptime: 31), capture)
        XCTAssertNil(store.consume(destinationURL: destination, uptime: 31))
    }

    func testDownloadSourceMessageRejectsUntrustedContracts() throws {
        let body: [String: Any] = [
            "version": 1,
            "kind": "activation",
            "href": "https://example.com/file.bin",
            "minX": 0.1,
            "minY": 0.2,
            "width": 0.3,
            "height": 0.1,
            "touchX": 0.15,
            "touchY": 0.25,
        ]
        XCTAssertNotNil(BrowserDownloadSourceCapture(messageBody: body))
        XCTAssertNil(
            BrowserDownloadSourceCapture(
                messageBody: body.merging(["version": 2]) { _, new in new }
            )
        )
        XCTAssertNil(
            BrowserDownloadSourceCapture(
                messageBody: body.merging(["href": "javascript:alert(1)"]) { _, new in new }
            )
        )
    }

    private func fixedID(_ byte: UInt8) -> UUID {
        UUID(
            uuid: (
                byte, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ))
    }
}
