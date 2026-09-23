import XCTest

@testable import Crest

@MainActor
final class BrowserEngineDownloadTests: XCTestCase {
    private final class Controller: BrowserEngineDownloadControlling {
        var canceled: [BrowserEngineDownloadID] = []
        var removed: [BrowserEngineDownloadID] = []
        var approved: [String] = []
        func cancelDownload(_ id: BrowserEngineDownloadID) { canceled.append(id) }
        func removeDownload(_ id: BrowserEngineDownloadID) { removed.append(id) }
        func approveDownload(_ id: BrowserEngineDownloadID, warningToken: String) { approved.append(warningToken) }
    }

    private func update(_ id: BrowserEngineDownloadID, state: BrowserEngineDownloadUpdate.State = .downloading,
                        bytes: Int64 = 10) -> BrowserEngineDownloadUpdate {
        BrowserEngineDownloadUpdate(id: id, filename: "report.txt", destination: URL(fileURLWithPath: "/tmp/report.txt"),
            bytesReceived: bytes, totalBytes: 100, isPaused: false, state: state)
    }

    func testProfileAndSpaceOwnershipCannotBeReassignedByAnUpdate() {
        let center = BrowserDownloadCenter(), controller = Controller()
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let id = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "one")
        center.receiveEngineDownload(update(id), assignment: assignment, controller: controller)
        center.receiveEngineDownload(update(id, state: .finished, bytes: 100),
            assignment: BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: assignment.profileID), controller: controller)
        center.receiveEngineDownload(update(id, state: .finished, bytes: 100),
            assignment: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: UUID()), controller: controller)
        XCTAssertEqual(center.items.count, 1)
        XCTAssertEqual(center.items.first?.progress, 0.1)
        XCTAssertEqual(center.items.first?.state, .downloading)
    }

    func testRestoredRecordsKeepRetentionDateWithoutAcknowledgingNewTransfers() {
        let center = BrowserDownloadCenter(), controller = Controller()
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let liveID = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "new")
        let restoredID = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "restored")
        center.receiveEngineDownload(update(liveID), assignment: assignment, controller: controller)
        let originalDate = Date(timeIntervalSince1970: 1_000_000)
        var restored = update(restoredID, state: .finished, bytes: 100)
        restored.createdAt = originalDate
        restored.isRestored = true
        center.receiveEngineDownload(restored, assignment: assignment, controller: controller)
        XCTAssertEqual(center.items.first?.createdAt, originalDate)
        XCTAssertEqual(center.items.first?.state, .finished)
        XCTAssertEqual(center.unacknowledgedItems(for: assignment.profileID).count, 1)
        XCTAssertEqual(center.unacknowledgedItems(for: assignment.profileID).first?.state, .downloading)
    }

    func testCancelAndClearIgnoreLateEngineProgressAndCompletion() throws {
        let center = BrowserDownloadCenter(), controller = Controller()
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let id = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "one")
        center.receiveEngineDownload(update(id), assignment: assignment, controller: controller)
        let item = try XCTUnwrap(center.items.first)
        center.clear(item.id)
        XCTAssertEqual(center.items.count, 1)
        XCTAssertTrue(controller.removed.isEmpty)
        center.cancel(item.id)
        center.receiveEngineDownload(update(id, state: .finished, bytes: 100), assignment: assignment, controller: controller)
        XCTAssertEqual(controller.canceled, [id])
        XCTAssertEqual(center.items.first?.state, .canceled("Canceled."))
        center.clear(item.id)
        XCTAssertEqual(controller.removed, [id])
        center.receiveEngineDownload(update(id), assignment: assignment, controller: controller)
        XCTAssertTrue(center.items.isEmpty)
    }

    func testProfileDeletionCancelsItsTransferAndPreservesOtherProfiles() {
        let center = BrowserDownloadCenter(), controller = Controller()
        let first = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let second = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let firstID = BrowserEngineDownloadID(engine: .chromium, profileID: first.profileID, value: "one")
        let secondID = BrowserEngineDownloadID(engine: .chromium, profileID: second.profileID, value: "one")
        center.receiveEngineDownload(update(firstID), assignment: first, controller: controller)
        center.receiveEngineDownload(update(secondID), assignment: second, controller: controller)
        center.deleteRecords(profileID: first.profileID, spaceID: first.spaceID)
        center.receiveEngineDownload(update(firstID, state: .finished), assignment: first, controller: controller)
        XCTAssertEqual(controller.canceled, [firstID])
        XCTAssertEqual(controller.removed, [firstID])
        XCTAssertEqual(center.items.map(\.profileID), [second.profileID])
    }

    func testCancelWhileChoosingDestinationNeverReturnsAWritePath() async throws {
        var continuation: CheckedContinuation<BrowserPlatformDownloadResolution, Never>?
        let entered = expectation(description: "Destination requested")
        let center = BrowserDownloadCenter(resolveDownloadDestination: { _, _, _ in
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        })
        let controller = Controller()
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let id = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "one")
        center.receiveEngineDownload(update(id), assignment: assignment, controller: controller)
        let task = Task { await center.resolveEngineDownloadDestination(id, suggestedFilename: "report.txt", forcesPrompt: true) }
        await fulfillment(of: [entered], timeout: 2)
        center.cancel(try XCTUnwrap(center.items.first).id)
        continuation?.resume(returning: .destination(URL(fileURLWithPath: "/tmp/report.txt"), securityScopedURL: nil))
        let destination = await task.value
        XCTAssertNil(destination)
        XCTAssertEqual(controller.canceled, [id])
    }

    func testSafetyApprovalIsDiscardedAfterTheEngineVerdictChanges() async {
        var continuation: CheckedContinuation<Bool, Never>?
        let entered = expectation(description: "Warning presented")
        let center = BrowserDownloadCenter(approveEngineDownload: { _, _ in
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        })
        let controller = Controller()
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let id = BrowserEngineDownloadID(engine: .chromium, profileID: assignment.profileID, value: "one")
        center.receiveEngineDownload(update(id, state: .awaitingApproval(token: "warning", message: "Uncommon file")),
            assignment: assignment, controller: controller)
        await fulfillment(of: [entered], timeout: 2)
        center.receiveEngineDownload(update(id, state: .failed("Blocked by policy")), assignment: assignment, controller: controller)
        continuation?.resume(returning: true)
        await Task.yield()
        XCTAssertTrue(controller.approved.isEmpty)
        XCTAssertEqual(center.items.first?.state, .failed("Blocked by policy"))
    }
}
