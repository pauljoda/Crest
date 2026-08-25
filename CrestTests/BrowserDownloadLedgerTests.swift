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

    func testTracksDestinationProgressAndCompletion() {
        var ledger = BrowserDownloadLedger()
        let profileID = UUID()
        let itemID = ledger.begin(profileID: profileID, filename: "report.pdf")
        let destination = URL(fileURLWithPath: "/Downloads/report.pdf")

        ledger.setDestination(destination, for: itemID)
        ledger.setProgress(0.45, for: itemID)

        XCTAssertEqual(ledger.items[0].destinationURL, destination)
        XCTAssertEqual(ledger.items[0].progress, 0.45)
        XCTAssertEqual(ledger.items[0].state, .downloading)

        ledger.finish(itemID)

        XCTAssertEqual(ledger.items[0].progress, 1)
        XCTAssertEqual(ledger.items[0].state, .finished)
    }

    func testRetainsTheFailureReason() {
        var ledger = BrowserDownloadLedger()
        let itemID = ledger.begin(profileID: UUID(), filename: "report.pdf")

        ledger.fail(itemID, message: "The destination is unavailable.")

        XCTAssertEqual(
            ledger.items[0].state,
            .failed("The destination is unavailable.")
        )
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

    func testCompletedRecordCanBeClearedWithoutAffectingAnotherProfile() {
        var ledger = BrowserDownloadLedger()
        let workProfileID = UUID()
        let personalProfileID = UUID()
        let workItemID = ledger.begin(profileID: workProfileID, filename: "work.pdf")
        _ = ledger.begin(profileID: personalProfileID, filename: "personal.pdf")

        ledger.finish(workItemID)
        ledger.remove(workItemID)

        XCTAssertTrue(ledger.items(for: workProfileID).isEmpty)
        XCTAssertEqual(ledger.items(for: personalProfileID).map(\.filename), ["personal.pdf"])
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

    func testBenignRiskAssessmentUpdatesMetadataWithoutAdvancingState() throws {
        var ledger = BrowserDownloadLedger()
        let itemID = ledger.begin(profileID: UUID(), filename: "../report.pdf")
        let assessment = BrowserDownloadRiskAssessment.assess(
            suggestedFilename: "../report.pdf",
            mimeType: "application/pdf"
        )

        ledger.setRiskAssessment(assessment, for: itemID)

        let item = try XCTUnwrap(ledger.items.first)
        XCTAssertEqual(item.filename, "report.pdf")
        XCTAssertEqual(item.riskAssessment, assessment)
        XCTAssertEqual(item.state, .preparing)
    }

    func testRestartMakesAnAcknowledgedDownloadVisibleAgain() {
        var ledger = BrowserDownloadLedger()
        let profileID = UUID()
        let itemID = ledger.begin(profileID: profileID, filename: "Emerald.dmg")
        ledger.blockAutomaticDownload(itemID)
        ledger.acknowledgeItems(for: profileID)

        XCTAssertTrue(ledger.unacknowledgedItems(for: profileID).isEmpty)

        ledger.restart(itemID)

        XCTAssertEqual(ledger.unacknowledgedItems(for: profileID).map(\.id), [itemID])
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

    func testTransferEstimatorHandlesUnknownAndIncorrectTotalsHonestly() {
        var estimator = BrowserDownloadTransferEstimator()
        let unknown = estimator.sample(
            completedUnitCount: 500,
            totalUnitCount: -1,
            fractionCompleted: 0.2,
            isPaused: false,
            uptime: 1
        )
        let incorrect = estimator.sample(
            completedUnitCount: 700,
            totalUnitCount: 600,
            fractionCompleted: 0.3,
            isPaused: false,
            uptime: 2
        )

        XCTAssertNil(unknown.telemetry.totalBytes)
        XCTAssertNil(unknown.telemetry.estimatedTimeRemaining)
        XCTAssertEqual(unknown.progress, 0.2, accuracy: 0.001)
        XCTAssertNil(incorrect.telemetry.totalBytes)
        XCTAssertEqual(incorrect.telemetry.bytesReceived, 700)
    }

    func testPausedAndTerminalTransfersNeverClaimActiveRateOrETA() throws {
        var estimator = BrowserDownloadTransferEstimator()
        _ = estimator.sample(
            completedUnitCount: 0,
            totalUnitCount: 1_000,
            fractionCompleted: 0,
            isPaused: false,
            uptime: 0
        )
        let active = estimator.sample(
            completedUnitCount: 250,
            totalUnitCount: 1_000,
            fractionCompleted: 0.25,
            isPaused: false,
            uptime: 1
        )
        let paused = estimator.sample(
            completedUnitCount: 250,
            totalUnitCount: 1_000,
            fractionCompleted: 0.25,
            isPaused: true,
            uptime: 2
        )
        XCTAssertNotNil(active.telemetry.bytesPerSecond)
        XCTAssertTrue(paused.telemetry.isPaused)
        XCTAssertNil(paused.telemetry.bytesPerSecond)
        XCTAssertNil(paused.telemetry.estimatedTimeRemaining)

        var ledger = BrowserDownloadLedger()
        let itemID = ledger.begin(profileID: UUID(), filename: "transfer.bin")
        ledger.setDestination(URL(fileURLWithPath: "/Downloads/transfer.bin"), for: itemID)
        ledger.setTransferUpdate(active, for: itemID)
        ledger.fail(itemID, message: "Connection lost.")
        let failed = try XCTUnwrap(ledger.items.first)
        XCTAssertNil(failed.telemetry.bytesPerSecond)
        XCTAssertNil(failed.telemetry.estimatedTimeRemaining)

        ledger.restart(itemID)
        XCTAssertEqual(ledger.items.first?.telemetry, .empty)
        ledger.finish(itemID, finalByteCount: 0)
        let completed = try XCTUnwrap(ledger.items.first)
        XCTAssertEqual(completed.telemetry.bytesReceived, 0)
        XCTAssertEqual(completed.telemetry.totalBytes, 0)
        XCTAssertNil(completed.telemetry.bytesPerSecond)
    }

    func testAcknowledgementIsIdempotentAcrossCompletionAndRecreationReads() {
        var ledger = BrowserDownloadLedger()
        let profileID = UUID()
        let itemID = ledger.begin(profileID: profileID, filename: "one.bin")

        XCTAssertEqual(ledger.acknowledgeItems(for: profileID), 1)
        XCTAssertEqual(ledger.acknowledgeItems(for: profileID), 0)
        ledger.finish(itemID, finalByteCount: 10)
        XCTAssertTrue(ledger.unacknowledgedItems(for: profileID).isEmpty)

        let recreatedViewRead = ledger
        XCTAssertTrue(recreatedViewRead.unacknowledgedItems(for: profileID).isEmpty)
        XCTAssertTrue(BrowserDownloadLedger().items(for: profileID).isEmpty)
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

    func testDownloadSourceStoreMatchesConcurrentActivationsIndependently() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first.bin"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second.bin"))
        let first = BrowserDownloadSourceCapture(
            destinationURL: firstURL,
            normalizedSourceRect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
            normalizedTouchPoint: CGPoint(x: 0.15, y: 0.25)
        )
        let second = BrowserDownloadSourceCapture(
            destinationURL: secondURL,
            normalizedSourceRect: CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.1),
            normalizedTouchPoint: CGPoint(x: 0.65, y: 0.75)
        )
        var store = BrowserDownloadSourceStore(maximumAge: 2)

        store.record(first, uptime: 10)
        store.record(second, uptime: 10.1)

        XCTAssertEqual(store.consume(destinationURL: secondURL, uptime: 10.5), second)
        XCTAssertEqual(store.consume(destinationURL: firstURL, uptime: 10.6), first)
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

    func testDownloadFeedbackPolicyUsesHonestFallbackAndReduceMotion() {
        XCTAssertEqual(
            BrowserDownloadFeedbackPolicy.presentation(
                hasSource: true,
                hasSidebarDestination: true,
                reduceMotion: false
            ),
            .flight
        )
        XCTAssertEqual(
            BrowserDownloadFeedbackPolicy.presentation(
                hasSource: true,
                hasSidebarDestination: true,
                reduceMotion: true
            ),
            .destinationFade
        )
        XCTAssertEqual(
            BrowserDownloadFeedbackPolicy.presentation(
                hasSource: false,
                hasSidebarDestination: true,
                reduceMotion: false
            ),
            .none
        )
        XCTAssertEqual(
            BrowserDownloadFeedbackPolicy.presentation(
                hasSource: true,
                hasSidebarDestination: false,
                reduceMotion: false
            ),
            .none
        )
    }

    func testOnlyTrustedDownloadGeometryStrengthensUserInitiation() {
        XCTAssertEqual(
            BrowserDownloadInitiationPolicy.userInitiatedOverride(
                hasTrustedSource: true
            ),
            true
        )
        XCTAssertNil(
            BrowserDownloadInitiationPolicy.userInitiatedOverride(
                hasTrustedSource: false
            )
        )
    }

    func testDownloadFeedbackQueueIsBoundedForSimultaneousDownloads() {
        let profileID = UUID()
        let spaceID = SpaceID(rawValue: UUID())
        var events: [BrowserDownloadFeedbackEvent] = []
        for index in 0..<8 {
            events = BrowserDownloadFeedbackPolicy.bounded(
                events,
                appending: BrowserDownloadFeedbackEvent(
                    id: UUID(),
                    profileID: profileID,
                    spaceID: spaceID,
                    filename: "\(index).bin",
                    source: BrowserDownloadFeedbackSource(
                        pointInGlobal: .zero,
                        windowIdentifier: nil
                    )
                )
            )
        }
        XCTAssertEqual(events.count, BrowserDownloadFeedbackPolicy.maximumVisibleEvents)
        XCTAssertEqual(events.map(\.filename), ["5.bin", "6.bin", "7.bin"])
    }

    func testDownloadRowPresentationAdaptsAndSuppressesStoppedTelemetry() throws {
        var item = BrowserDownloadItem(
            id: UUID(),
            profileID: UUID(),
            createdAt: .now,
            filename: "large.bin",
            destinationURL: nil,
            progress: 0.5,
            state: .downloading,
            riskAssessment: nil
        )
        item.telemetry = BrowserDownloadTransferTelemetry(
            bytesReceived: 500,
            totalBytes: 1_000,
            bytesPerSecond: 100,
            estimatedTimeRemaining: 5,
            isPaused: false
        )
        let active = BrowserDownloadRowPresentation.resolve(item: item)
        XCTAssertEqual(active.bytesReceived, 500)
        XCTAssertEqual(active.totalBytes, 1_000)
        XCTAssertEqual(active.bytesPerSecond, 100)
        XCTAssertEqual(
            BrowserDownloadRowLayoutPolicy.resolve(
                availableWidth: 500,
                usesAccessibilityTextSize: false,
                hasSecondaryMetrics: active.hasSecondaryTransferMetrics,
                statusNeedsAttention: active.statusNeedsAttention
            ),
            .inline
        )
        XCTAssertEqual(
            BrowserDownloadRowLayoutPolicy.resolve(
                availableWidth: 240,
                usesAccessibilityTextSize: false,
                hasSecondaryMetrics: active.hasSecondaryTransferMetrics,
                statusNeedsAttention: active.statusNeedsAttention
            ),
            .stacked
        )
        XCTAssertEqual(
            BrowserDownloadRowLayoutPolicy.resolve(
                availableWidth: 500,
                usesAccessibilityTextSize: true,
                hasSecondaryMetrics: active.hasSecondaryTransferMetrics,
                statusNeedsAttention: active.statusNeedsAttention
            ),
            .stacked
        )

        item.state = .canceled("Canceled.")
        let canceled = BrowserDownloadRowPresentation.resolve(item: item)
        XCTAssertNil(canceled.bytesPerSecond)
        XCTAssertNil(canceled.estimatedTimeRemaining)
        XCTAssertTrue(canceled.showsStatusAlongsideMetrics)
    }

    private func fixedID(_ byte: UInt8) -> UUID {
        UUID(
            uuid: (
                byte, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ))
    }
}
