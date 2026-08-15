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

    func testAutomaticDownloadsRespectSavedDecisionOrRequestPermission() {
        let expectations: [(BrowserSitePermissionDecision, BrowserAutomaticDownloadAction)] = [
            (.ask, .requestPermission),
            (.grantForSession, .allow),
            (.grantPersistently, .allow),
            (.denyForSession, .deny),
            (.denyPersistently, .deny),
        ]
        for (decision, expectedAction) in expectations {
            XCTAssertEqual(
                BrowserAutomaticDownloadPolicy.action(
                    isUserInitiated: false,
                    savedDecision: decision
                ),
                expectedAction,
                "Unexpected action for \(decision)"
            )
        }
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

    private func fixedID(_ byte: UInt8) -> UUID {
        UUID(
            uuid: (
                byte, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ))
    }
}
