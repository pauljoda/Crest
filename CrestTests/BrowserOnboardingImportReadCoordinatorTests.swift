import XCTest
@testable import Crest

@MainActor
final class BrowserOnboardingImportReadCoordinatorTests: XCTestCase {
    func testOlderReadCannotPublishOrClearLoadingAfterANewerReadStarts() async {
        let reader = SuspendedBrowserOnboardingImportReader()
        let coordinator = BrowserOnboardingImportReadCoordinator(reader: reader)
        let recorder = BrowserOnboardingImportReadRecorder()
        let safari = payload(for: .safari)
        let chrome = payload(for: .chrome)

        coordinator.startReading(
            safari,
            onFinish: recorder.recordFinish,
            completion: recorder.record
        )
        await reader.waitUntilStarted(.safari)
        coordinator.startReading(
            chrome,
            onFinish: recorder.recordFinish,
            completion: recorder.record
        )
        await reader.waitUntilStarted(.chrome)

        await reader.complete(.safari)
        await waitUntil { recorder.finishCount == 1 }

        XCTAssertTrue(coordinator.isInFlight)
        XCTAssertEqual(coordinator.phase.application, .chrome)
        XCTAssertTrue(recorder.successfulApplications.isEmpty)
        XCTAssertTrue(recorder.errorDescriptions.isEmpty)

        await reader.complete(.chrome)
        await waitUntil { !coordinator.isInFlight }

        XCTAssertEqual(recorder.successfulApplications, [.chrome])
        XCTAssertTrue(recorder.errorDescriptions.isEmpty)
        XCTAssertEqual(recorder.finishCount, 2)
    }

    func testCancellationIgnoresAReaderThatDoesNotCooperateWithTaskCancellation() async {
        let reader = SuspendedBrowserOnboardingImportReader()
        let coordinator = BrowserOnboardingImportReadCoordinator(reader: reader)
        let recorder = BrowserOnboardingImportReadRecorder()

        coordinator.startReading(
            payload(for: .safari),
            onFinish: recorder.recordFinish,
            completion: recorder.record
        )
        await reader.waitUntilStarted(.safari)

        coordinator.cancel()

        XCTAssertFalse(coordinator.isInFlight)
        XCTAssertNil(coordinator.phase.application)

        await reader.complete(.safari)
        await waitUntil { recorder.finishCount == 1 }

        XCTAssertTrue(recorder.successfulApplications.isEmpty)
        XCTAssertTrue(recorder.errorDescriptions.isEmpty)
    }

    func testPhaseProvidesOneInFlightStateForImportControlAvailability() async {
        let reader = SuspendedBrowserOnboardingImportReader()
        let coordinator = BrowserOnboardingImportReadCoordinator(reader: reader)

        XCTAssertFalse(coordinator.isInFlight)

        coordinator.startReading(payload(for: .arc)) { _ in }
        await reader.waitUntilStarted(.arc)

        XCTAssertTrue(coordinator.isInFlight)
        XCTAssertEqual(coordinator.phase.application, .arc)

        await reader.complete(.arc)
        await waitUntil { !coordinator.isInFlight }

        XCTAssertFalse(coordinator.isInFlight)
        XCTAssertNil(coordinator.phase.application)
    }

    private func payload(
        for application: BrowserImportApplication
    ) -> BrowserDetectedImportPayload {
        BrowserDetectedImportPayload(application: application, profiles: [])
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        predicate: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for onboarding import state")
    }
}

@MainActor
private final class BrowserOnboardingImportReadRecorder {
    private(set) var successfulApplications: [BrowserImportApplication] = []
    private(set) var errorDescriptions: [String] = []
    private(set) var finishCount = 0

    func record(
        _ result: Result<BrowserOnboardingImportReadOutput, any Error>
    ) {
        switch result {
        case .success(let output):
            successfulApplications.append(output.payload.application)
        case .failure(let error):
            errorDescriptions.append(error.localizedDescription)
        }
    }

    func recordFinish() {
        finishCount += 1
    }
}

private actor SuspendedBrowserOnboardingImportReader:
    BrowserOnboardingImportReading
{
    private struct PendingRead {
        let payload: BrowserDetectedImportPayload
        let continuation: CheckedContinuation<
            BrowserOnboardingImportReadOutput,
            Error
        >
    }

    private var pendingReads: [BrowserImportApplication: PendingRead] = [:]
    private var startWaiters: [
        BrowserImportApplication: [CheckedContinuation<Void, Never>]
    ] = [:]

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        try await withCheckedThrowingContinuation { continuation in
            pendingReads[payload.application] = PendingRead(
                payload: payload,
                continuation: continuation
            )
            let waiters = startWaiters.removeValue(forKey: payload.application) ?? []
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilStarted(_ application: BrowserImportApplication) async {
        guard pendingReads[application] == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters[application, default: []].append(continuation)
        }
    }

    func complete(_ application: BrowserImportApplication) {
        guard let pending = pendingReads.removeValue(forKey: application) else {
            return
        }
        pending.continuation.resume(
            returning: BrowserOnboardingImportReadOutput(
                payload: pending.payload,
                imported: BrowserPortableImport(
                    spaces: [],
                    summary: BrowserPortableImportSummary(
                        spaceCount: 0,
                        folderCount: 0,
                        liveTabCount: 0,
                        archivedTabCount: 0,
                        historyEntryCount: 0
                    )
                ),
                passwordCandidates: []
            )
        )
    }
}
