import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceOrderActionsTests: XCTestCase {
    func testMoveResolvesTheCurrentSpaceOrderAndPersistsWithoutChangingSpaceContents() throws {
        var session = BrowserSession.preview
        session.spaces.append(BrowserSession.makeBlankSpace(number: session.spaces.count + 1))
        let originalSpaces = session.spaces
        let movedID = originalSpaces[0].id
        session.defaultSpaceID = originalSpaces[1].id
        let browser = BrowserStore(session: session)
        let shownSpaceID = browser.selectedSpaceID
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: movedID)
        XCTAssertFalse(actions.canMoveUp)
        XCTAssertTrue(actions.canMoveDown)

        browser.moveSpaces(from: IndexSet(integer: 0), to: session.spaces.count)
        actions.moveUp()

        XCTAssertEqual(browser.session.spaces.map(\.id), [originalSpaces[1].id, movedID, originalSpaces[2].id])
        XCTAssertEqual(browser.selectedSpaceID, shownSpaceID)
        XCTAssertEqual(browser.session.defaultSpaceID, session.defaultSpaceID)
        for original in originalSpaces {
            XCTAssertEqual(browser.session.space(id: original.id), original)
        }

        actions.moveDown()
        XCTAssertEqual(browser.session.spaces.last?.id, movedID)
        XCTAssertFalse(actions.canMoveDown)
        let revision = browser.family.syncRevision
        actions.moveDown()
        let missing = BrowserSpaceOrderActions(browser: browser, spaceID: SpaceID())
        XCTAssertFalse(missing.canMoveUp)
        XCTAssertFalse(missing.canMoveDown)
        missing.moveUp()
        missing.moveDown()
        XCTAssertEqual(browser.family.syncRevision, revision, "A move that cannot happen stages nothing")
    }
}
