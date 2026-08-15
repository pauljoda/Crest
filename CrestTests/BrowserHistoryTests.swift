import Foundation
import XCTest
@testable import Crest

final class BrowserHistoryTests: XCTestCase {
    func testVisitsBelongOnlyToTheSelectedSpace() throws {
        var session = BrowserSession.preview
        let workID = session.selectedSpaceID
        let personalID = try XCTUnwrap(session.spaces.last?.id)

        session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/work")),
            title: "Work",
            at: Date(timeIntervalSince1970: 100)
        )
        session.selectSpace(personalID)
        session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/personal")),
            title: "Personal",
            at: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(session.space(id: workID)?.history.map(\.title), ["Work"])
        XCTAssertEqual(session.space(id: personalID)?.history.map(\.title), ["Personal"])
    }

    func testRepeatedVisitMergesByURLAndUpdatesRecency() throws {
        var session = BrowserSession.preview
        let url = try XCTUnwrap(URL(string: "https://example.com/article#section"))

        session.recordVisit(url: url, title: "First title", at: Date(timeIntervalSince1970: 100))
        session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/article#other")),
            title: "Updated title",
            at: Date(timeIntervalSince1970: 200)
        )

        let entry = try XCTUnwrap(session.selectedSpace?.history.first)
        XCTAssertEqual(try XCTUnwrap(session.selectedSpace).history.count, 1)
        XCTAssertEqual(entry.url.absoluteString, "https://example.com/article")
        XCTAssertEqual(entry.title, "Updated title")
        XCTAssertEqual(entry.visitCount, 2)
        XCTAssertEqual(entry.firstVisitedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(entry.lastVisitedAt, Date(timeIntervalSince1970: 200))
    }

    func testClearingHistoryAffectsOnlyTheSelectedSpace() throws {
        var session = BrowserSession.preview
        let workID = session.selectedSpaceID
        let personalID = try XCTUnwrap(session.spaces.last?.id)
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        session.recordVisit(url: url, title: "Work", at: .now)
        session.selectSpace(personalID)
        session.recordVisit(url: url, title: "Personal", at: .now)
        session.clearHistory()

        XCTAssertEqual(session.space(id: workID)?.history.count, 1)
        XCTAssertTrue(try XCTUnwrap(session.space(id: personalID)).history.isEmpty)
    }

    func testLegacySpaceWithoutHistoryDecodesWithEmptyHistory() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let encoded = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "history")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertTrue(decoded.history.isEmpty)
    }
}
