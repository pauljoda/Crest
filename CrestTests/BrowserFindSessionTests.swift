import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserFindSessionTests: XCTestCase {
    func testPresentationRequiresLoadedContent() {
        let session = BrowserFindSession()

        session.present(hasLoadedPage: false)
        XCTAssertFalse(session.isPresented)

        session.present(hasLoadedPage: true)
        XCTAssertTrue(session.isPresented)
    }

    func testSearchConfiguresNativeFindAndPublishesItsResult() throws {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.find("Crest", direction: .backward, using: executor)

        let request = try XCTUnwrap(executor.requests.first)
        XCTAssertEqual(request.query, "Crest")
        XCTAssertTrue(request.configuration.backwards)
        XCTAssertFalse(request.configuration.caseSensitive)
        XCTAssertTrue(request.configuration.wraps)
        XCTAssertEqual(session.matchState, .searching)

        executor.completeRequest(at: 0, matchFound: true)
        XCTAssertEqual(session.matchState, .found)
    }

    func testNewerSearchSupersedesAnOlderCompletion() {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.find("first", using: executor)
        session.find("second", using: executor)

        executor.completeRequest(at: 1, matchFound: true)
        XCTAssertEqual(session.matchState, .found)

        executor.completeRequest(at: 0, matchFound: false)
        XCTAssertEqual(session.matchState, .found)
    }

    func testEmptySearchAndDismissClearNativeFindState() {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.present(hasLoadedPage: true)
        session.find("", using: executor)

        XCTAssertEqual(executor.requests.map(\.query), [""])
        XCTAssertEqual(session.matchState, .idle)
        XCTAssertTrue(session.isPresented)

        session.dismiss(using: executor)

        XCTAssertEqual(executor.requests.map(\.query), ["", ""])
        XCTAssertEqual(session.matchState, .idle)
        XCTAssertFalse(session.isPresented)
    }
}

@MainActor
private final class BrowserFindExecutorSpy: BrowserFindExecuting {
    struct Request {
        let query: String
        let configuration: WKFindConfiguration
        let completion: @MainActor (Bool) -> Void
    }

    private(set) var requests: [Request] = []

    func performFind(
        _ query: String,
        configuration: WKFindConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        requests.append(
            Request(
                query: query,
                configuration: configuration,
                completion: completion
            )
        )
    }

    func completeRequest(at index: Int, matchFound: Bool) {
        requests[index].completion(matchFound)
    }
}
