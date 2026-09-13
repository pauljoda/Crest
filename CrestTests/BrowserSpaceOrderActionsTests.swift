import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceOrderActionsTests: XCTestCase {
    func testMoveResolvesTheCurrentSpaceOrderAndPersistsWithoutChangingSpaceContents() throws {
        var session = BrowserSession.preview
        session.addSpace()
        let originalSpaces = session.spaces
        let movedID = originalSpaces[0].id
        session.defaultSpaceID = originalSpaces[1].id
        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(session: session, persistence: persistence)
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: movedID)
        XCTAssertFalse(actions.canMoveUp)
        XCTAssertTrue(actions.canMoveDown)

        browser.moveSpaces(from: IndexSet(integer: 0), to: session.spaces.count)
        actions.moveUp()

        XCTAssertEqual(browser.session.spaces.map(\.id), [originalSpaces[1].id, movedID, originalSpaces[2].id])
        XCTAssertEqual(browser.session.selectedSpaceID, session.selectedSpaceID)
        XCTAssertEqual(browser.session.defaultSpaceID, session.defaultSpaceID)
        for original in originalSpaces {
            XCTAssertEqual(browser.session.space(id: original.id), original)
        }
        XCTAssertEqual(try XCTUnwrap(persistence.load()), browser.session)
        XCTAssertEqual(persistence.savedScopes.last, .core)

        actions.moveDown()
        XCTAssertEqual(browser.session.spaces.last?.id, movedID)
        XCTAssertFalse(actions.canMoveDown)
        let savedCount = persistence.savedScopes.count
        actions.moveDown()
        let missing = BrowserSpaceOrderActions(browser: browser, spaceID: SpaceID())
        XCTAssertFalse(missing.canMoveUp)
        XCTAssertFalse(missing.canMoveDown)
        missing.moveUp()
        missing.moveDown()
        XCTAssertEqual(persistence.savedScopes.count, savedCount)
    }
}
