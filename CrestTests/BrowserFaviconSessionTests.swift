import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconSessionTests: XCTestCase {
    func testAutomaticRefreshDoesNotRepeatMissingIconWorkUntilDocumentInvalidation() async {
        let document = SuspendedFaviconDocument()
        document.suspendsCapture = false
        document.suspendsFallback = false
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Missing icon published") })
        let first = await session.pull()
        XCTAssertNil(first)

        let repeated = expectation(description: "Unchanged document must not start another capture")
        repeated.isInverted = true
        document.captureStarted = { repeated.fulfill() }
        for _ in 0..<50 { session.refresh() }
        await fulfillment(of: [repeated], timeout: 0.1)
        XCTAssertEqual(document.captureCount, 1)
        XCTAssertEqual(document.fallbackCount, 1)

        // A reload can replace the document without changing its URL.
        session.invalidate()
        let reloaded = expectation(description: "Replacement document starts a capture")
        document.captureStarted = { reloaded.fulfill() }
        session.refresh()
        await fulfillment(of: [reloaded], timeout: 1)
        XCTAssertEqual(document.captureCount, 2)
    }

    func testAutomaticRefreshPreservesInFlightCaptureAndDelayedIconRetries() async {
        let document = SuspendedFaviconDocument()
        document.suspendsFallback = false
        let session = BrowserFaviconSession(
            document: document,
            policy: .init(retryDelays: [.milliseconds(1)]),
            wait: { _ in
                document.suspendsCapture = false
                document.captureData = Data([7])
            },
            receive: { _ in }
        )
        let started = expectation(description: "Capture started")
        document.captureStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)
        document.captureStarted = nil
        document.suspendsCapture = false

        for _ in 0..<50 { session.refresh() }
        document.finishCapture(nil)
        let result = await request.value

        XCTAssertEqual(result, Data([7]))
        XCTAssertEqual(document.captureCount, 2)
        XCTAssertEqual(document.fallbackCount, 1)
        session.stop()
    }

    func testNavigationPreventsOldCaptureFromStartingFallback() async {
        let document = SuspendedFaviconDocument()
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Stale icon published") })
        let started = expectation(description: "Capture started")
        document.captureStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        // A reload may replace the document without changing its URL.
        session.invalidate()
        document.finishCapture(nil)
        let result = await request.value

        XCTAssertNil(result)
        XCTAssertEqual(document.fallbackCount, 0)
    }

    func testChangedURLRejectsCaptureEvenBeforeNavigationCallback() async {
        let document = SuspendedFaviconDocument()
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Stale icon published") })
        let started = expectation(description: "Capture started")
        document.captureStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        document.url = URL(string: "https://replacement.crest.test/")
        document.finishCapture(nil)
        let result = await request.value

        XCTAssertNil(result)
        XCTAssertEqual(document.fallbackCount, 0)
    }

    func testRemovalDuringFallbackRejectsCompletionAndFurtherRequests() async {
        let document = SuspendedFaviconDocument()
        document.suspendsCapture = false
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Removed page published") })
        let started = expectation(description: "Fallback started")
        document.fallbackStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        session.stop()
        document.finishFallback(Data([1]))
        let result = await request.value
        let laterResult = await session.pull()
        session.refresh()
        await Task.yield()

        XCTAssertNil(result)
        XCTAssertNil(laterResult)
        XCTAssertEqual(document.captureCount, 1)
        XCTAssertEqual(document.fallbackCount, 1)
    }

    func testCallerCancellationPreventsFallbackAndPublication() async {
        let document = SuspendedFaviconDocument()
        var received: [Data] = []
        let refreshed = expectation(description: "Later refresh can capture after caller cancellation")
        let session = BrowserFaviconSession(document: document) {
            received.append($0)
            refreshed.fulfill()
        }
        let started = expectation(description: "Capture started")
        document.captureStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        request.cancel()
        document.finishCapture(nil)
        let result = await request.value

        XCTAssertNil(result)
        XCTAssertEqual(document.fallbackCount, 0)
        XCTAssertTrue(received.isEmpty)

        document.suspendsCapture = false
        document.captureStarted = nil
        document.captureData = Data([2])
        session.refresh()
        await fulfillment(of: [refreshed], timeout: 1)
        XCTAssertEqual(received, [Data([2])])
    }

    func testNewerRequestOwnsPublicationAndMissingCaptureKeepsLastIcon() async {
        let document = SuspendedFaviconDocument()
        var icon = Data([1])
        let session = BrowserFaviconSession(document: document, receive: { icon = $0 })
        let started = expectation(description: "Older capture started")
        document.captureStarted = { started.fulfill() }
        let oldRequest = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)
        document.captureStarted = nil

        document.suspendsCapture = false
        document.captureData = Data([2])
        let current = await session.pull()
        document.finishCapture(Data([3]))
        let old = await oldRequest.value

        XCTAssertEqual(current, Data([2]))
        XCTAssertNil(old)
        XCTAssertEqual(icon, Data([2]))

        document.captureData = nil
        document.suspendsFallback = false
        let missing = await session.pull()
        XCTAssertNil(missing)
        XCTAssertEqual(icon, Data([2]))
    }

    func testRetryStopsAfterInvalidationWithoutCapturingReplacementDocument() async {
        let document = SuspendedFaviconDocument()
        document.suspendsCapture = false
        document.suspendsFallback = false
        let waiting = expectation(description: "Retry waiting")
        var resumeRetry: CheckedContinuation<Void, Never>?
        let session = BrowserFaviconSession(
            document: document,
            policy: .init(retryDelays: [.seconds(1)]),
            wait: { _ in
                await withCheckedContinuation { continuation in
                    resumeRetry = continuation
                    waiting.fulfill()
                }
            },
            receive: { _ in XCTFail("Stale retry published") }
        )
        let request = Task { await session.pull() }
        await fulfillment(of: [waiting], timeout: 1)

        session.invalidate()
        resumeRetry?.resume()
        let result = await request.value

        XCTAssertNil(result)
        XCTAssertEqual(document.captureCount, 1)
        XCTAssertEqual(document.fallbackCount, 1)
    }

    func testDelayedDocumentIconUsesCaptureWithoutRepeatingPublicFallback() async {
        let document = SuspendedFaviconDocument()
        document.suspendsCapture = false
        document.suspendsFallback = false
        var icon: Data?
        let session = BrowserFaviconSession(
            document: document,
            policy: .init(retryDelays: [.seconds(1), .seconds(2)]),
            wait: { _ in document.captureData = Data([4]) },
            receive: { icon = $0 }
        )
        let result = await session.pull()

        XCTAssertEqual(result, Data([4]))
        XCTAssertEqual(icon, result)
        XCTAssertEqual(document.captureCount, 2)
        XCTAssertEqual(document.fallbackCount, 1)
    }
}

@MainActor
private final class SuspendedFaviconDocument: BrowserFaviconDocument {
    var url = URL(string: "https://favicon.crest.test/document")
    var suspendsCapture = true
    var suspendsFallback = true
    var captureData: Data?
    var captureStarted: (() -> Void)?
    var fallbackStarted: (() -> Void)?
    private(set) var captureCount = 0
    private(set) var fallbackCount = 0
    private var captureContinuation: CheckedContinuation<Data?, Never>?
    private var fallbackContinuation: CheckedContinuation<Data?, Never>?

    func capture() async -> Data? {
        captureCount += 1
        guard suspendsCapture else {
            captureStarted?()
            return captureData
        }
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            captureStarted?()
        }
    }

    func fallback(for url: URL) async -> Data? {
        fallbackCount += 1
        guard suspendsFallback else { return nil }
        return await withCheckedContinuation { continuation in
            fallbackContinuation = continuation
            fallbackStarted?()
        }
    }

    func finishCapture(_ data: Data?) {
        captureContinuation?.resume(returning: data)
        captureContinuation = nil
    }

    func finishFallback(_ data: Data?) {
        fallbackContinuation?.resume(returning: data)
        fallbackContinuation = nil
    }
}
