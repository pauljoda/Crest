import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadLedgerTests: XCTestCase {
    func testItemsAreScopedToTheirBrowsingProfile() {
        var ledger = BrowserDownloadLedger()
        let workProfileID = UUID()
        let personalProfileID = UUID()

        _ = ledger.begin(profileID: workProfileID, filename: "work.pdf")
        _ = ledger.begin(profileID: personalProfileID, filename: "personal.pdf")

        XCTAssertEqual(ledger.items(for: workProfileID).map(\.filename), ["work.pdf"])
        XCTAssertEqual(ledger.items(for: personalProfileID).map(\.filename), ["personal.pdf"])
    }

    func testRiskyDownloadWaitsForApprovalAndCanBeCanceled() {
        var ledger = BrowserDownloadLedger()
        let itemID = ledger.begin(profileID: UUID(), filename: "dangerous.command")
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "system-update.command",
            mimeType: "application/octet-stream"
        )

        ledger.setRiskAssessment(assessment, for: itemID)

        XCTAssertEqual(ledger.items[0].state, .awaitingApproval)
        XCTAssertEqual(ledger.items[0].filename, "system-update.command")
        XCTAssertEqual(ledger.items[0].riskAssessment, assessment)

        ledger.cancel(itemID, message: "Canceled for safety.")

        XCTAssertEqual(ledger.items[0].state, .canceled("Canceled for safety."))
    }

    func testRemovingAProfilesDownloadHistoryPreservesEveryOtherProfile() {
        var ledger = BrowserDownloadLedger()
        let deletedProfileID = UUID()
        let retainedProfileID = UUID()
        _ = ledger.begin(profileID: deletedProfileID, filename: "private.pdf")
        _ = ledger.begin(profileID: retainedProfileID, filename: "keep.pdf")

        ledger.removeAll(for: deletedProfileID)

        XCTAssertTrue(ledger.items(for: deletedProfileID).isEmpty)
        XCTAssertEqual(
            ledger.items(for: retainedProfileID).map(\.filename),
            ["keep.pdf"]
        )
    }

    func testOpeningDownloadsAcknowledgesTheBadgeWithoutClearingHistory() {
        var ledger = BrowserDownloadLedger()
        let profileID = UUID()
        let firstItemID = ledger.begin(profileID: profileID, filename: "first.pdf")
        let secondItemID = ledger.begin(profileID: profileID, filename: "second.pdf")

        XCTAssertEqual(
            Set(ledger.unacknowledgedItems(for: profileID).map(\.id)),
            [firstItemID, secondItemID]
        )

        ledger.acknowledgeItems(for: profileID)

        XCTAssertTrue(ledger.unacknowledgedItems(for: profileID).isEmpty)
        XCTAssertEqual(ledger.items(for: profileID).count, 2)

        let thirdItemID = ledger.begin(profileID: profileID, filename: "third.pdf")

        XCTAssertEqual(
            ledger.unacknowledgedItems(for: profileID).map(\.id),
            [thirdItemID]
        )
    }

    func testUserInitiatedDownloadsBypassAutomaticDownloadPermission() {
        XCTAssertEqual(
            BrowserAutomaticDownloadPolicy.action(
                isUserInitiated: true,
                savedDecision: .denyPersistently
            ),
            .allow
        )
    }

    func testFirstAutomaticDownloadIsAllowedBeforeAdditionalDownloadsAsk() {
        var sequence = BrowserAutomaticDownloadSequence()

        XCTAssertEqual(
            sequence.action(isUserInitiated: false, savedDecision: .ask),
            .allow
        )
        XCTAssertEqual(
            sequence.action(isUserInitiated: false, savedDecision: .ask),
            .requestPermission
        )
    }

    func testAutomaticDownloadsRespectSavedAllowAndBlockDecisions() {
        let expectations: [(BrowserSitePermissionDecision, BrowserAutomaticDownloadAction)] = [
            (.grantForSession, .allow),
            (.grantPersistently, .allow),
            (.denyForSession, .deny),
            (.denyPersistently, .deny),
        ]
        for (decision, expectedAction) in expectations {
            XCTAssertEqual(
                BrowserAutomaticDownloadPolicy.action(
                    isUserInitiated: false,
                    savedDecision: decision,
                    hasAllowedAutomaticDownload: true
                ),
                expectedAction,
                "Unexpected action for \(decision)"
            )
        }
    }

    func testAUserInitiatedDownloadResetsTheAutomaticDownloadAllowance() {
        var sequence = BrowserAutomaticDownloadSequence()
        XCTAssertEqual(
            sequence.action(isUserInitiated: false, savedDecision: .ask),
            .allow
        )
        XCTAssertEqual(
            sequence.action(isUserInitiated: true, savedDecision: .ask),
            .allow
        )
        XCTAssertEqual(
            sequence.action(isUserInitiated: false, savedDecision: .ask),
            .allow
        )
    }

    func testBeginningDownloadsPreservesInsertionOrderAndCreationDate() throws {
        var ledger = BrowserDownloadLedger()
        let profileID = UUID()
        let firstDate = Date(timeIntervalSinceReferenceDate: 100)
        let secondDate = Date(timeIntervalSinceReferenceDate: 200)
        let firstID = ledger.begin(
            profileID: profileID,
            filename: "first.pdf",
            createdAt: firstDate
        )
        let secondID = ledger.begin(
            profileID: profileID,
            filename: "second.pdf",
            createdAt: secondDate
        )

        XCTAssertEqual(
            ledger.items.map(\.id),
            [secondID, firstID]
        )
        XCTAssertEqual(ledger.items.map(\.createdAt), [secondDate, firstDate])
    }

    func testExplicitRetryOverridesAStoredAutomaticDownloadDenialOnce() {
        XCTAssertEqual(
            BrowserAutomaticDownloadPolicy.action(
                isUserInitiated: false,
                savedDecision: .denyPersistently,
                isUserApprovedRetry: true
            ),
            .allow
        )
    }

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

    func testBlockedAutomaticDownloadCanRestartWithoutKeepingFailedState() throws {
        var ledger = BrowserDownloadLedger()
        let itemID = ledger.begin(profileID: UUID(), filename: "Emerald.dmg")
        ledger.setRiskAssessment(
            BrowserDownloadRiskAssessment.assess(
                suggestedFilename: "Emerald.dmg",
                mimeType: "application/x-apple-diskimage"
            ),
            for: itemID
        )
        ledger.blockAutomaticDownload(itemID)

        XCTAssertEqual(ledger.items.first?.state, .blockedAutomaticDownload)

        ledger.restart(itemID)

        let restarted = try XCTUnwrap(ledger.items.first)
        XCTAssertEqual(restarted.state, .preparing)
        XCTAssertEqual(restarted.progress, 0)
        XCTAssertNil(restarted.destinationURL)
        XCTAssertNil(restarted.riskAssessment)
    }

    func testRetryRegistrationRequiresTheExactLiveLeaseContextAndLedgerItem() {
        let leaseID = fixedID(0x11)
        let itemID = fixedID(0x12)
        let profileID = fixedID(0x13)
        let spaceID = SpaceID(rawValue: fixedID(0x14))
        let lease = BrowserDownloadRetryLease(
            id: leaseID,
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID
        )
        let item = BrowserDownloadItem(
            id: itemID,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            filename: "report.pdf",
            destinationURL: nil,
            progress: 0,
            state: .preparing,
            riskAssessment: nil
        )

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
        let spaceID = SpaceID(rawValue: fixedID(0x23))
        let lease = BrowserDownloadRetryLease(
            id: fixedID(0x24),
            itemID: itemID,
            profileID: profileID,
            spaceID: spaceID
        )
        let item = BrowserDownloadItem(
            id: itemID,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            filename: "report.pdf",
            destinationURL: nil,
            progress: 0,
            state: .preparing,
            riskAssessment: nil
        )
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
        var completedItem = item
        completedItem.state = .finished
        var canceledItem = item
        canceledItem.state = .canceled("Canceled.")

        let rejectedInputs:
            [(
                BrowserDownloadRetryLease?, BrowserDownloadItem?, BrowserSpaceRuntimeAssignment?, Bool
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

    func testTransferEstimatorKeepsBytesMonotonicAndSmoothsRateAndETA() throws {
        var estimator = BrowserDownloadTransferEstimator()

        _ = estimator.sample(
            completedUnitCount: 0,
            totalUnitCount: 10_000,
            fractionCompleted: 0,
            isPaused: false,
            uptime: 0
        )
        let first = estimator.sample(
            completedUnitCount: 1_000,
            totalUnitCount: 10_000,
            fractionCompleted: 0.1,
            isPaused: false,
            uptime: 1
        )
        let noisy = estimator.sample(
            completedUnitCount: 3_000,
            totalUnitCount: 10_000,
            fractionCompleted: 0.3,
            isPaused: false,
            uptime: 2
        )
        let regressed = estimator.sample(
            completedUnitCount: 2_500,
            totalUnitCount: 10_000,
            fractionCompleted: 0.25,
            isPaused: false,
            uptime: 3
        )

        XCTAssertEqual(
            try XCTUnwrap(first.telemetry.bytesPerSecond),
            1_000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(first.telemetry.estimatedTimeRemaining),
            9,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(noisy.telemetry.bytesPerSecond),
            1_250,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(noisy.telemetry.estimatedTimeRemaining),
            5.6,
            accuracy: 0.001
        )
        XCTAssertEqual(regressed.telemetry.bytesReceived, 3_000)
        XCTAssertEqual(regressed.progress, 0.3, accuracy: 0.001)
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
