import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarInteractionStateTests: XCTestCase {
    func testPrivateResetClearsStagedAndActiveLiftsWithoutTouchingAnotherWindow() throws {
        let browser = BrowserStore.privateBrowsing()
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let otherBrowser = BrowserStore.preview()
        let other = BrowserSidebarInteractionState.connected(to: otherBrowser)
        let otherSpace = try XCTUnwrap(otherBrowser.selectedSpace)
        let otherTab = try XCTUnwrap(otherBrowser.selectedTab)
        other.sidebarReorderState.stage(
            item: .tab(
                BrowserTabDragItem(tabID: otherTab.id, spaceID: otherSpace.id, profileID: otherSpace.profile.id)),
            section: .tabs(placement: otherTab.placement, folderID: nil))

        for staged in [true, false] {
            let space = try XCTUnwrap(browser.selectedSpace)
            let tab = try XCTUnwrap(browser.selectedTab)
            let item = BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
            let section = BrowserSidebarReorderSection.tabs(placement: tab.placement, folderID: nil)
            if staged {
                interaction.sidebarReorderState.stage(item: .tab(item), section: section)
            } else {
                interaction.sidebarReorderState.begin(item: .tab(item), section: section, at: .zero)
            }
            interaction.tabDragState.begin(item: item, placement: tab.placement)

            browser.resetPrivateBrowsingSession()

            XCTAssertFalse(interaction.sidebarReorderState.hasLiftInFlight)
            XCTAssertNil(interaction.sidebarReorderState.liftPreview)
            XCTAssertNil(interaction.tabDragState.item)
            XCTAssertTrue(other.sidebarReorderState.hasLiftInFlight)
        }
        other.cancel()
    }

    func testRepeatedCompositionPreservesTheLiveInteractionObserver() throws {
        let browser = BrowserStore.privateBrowsing()
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        XCTAssertTrue(BrowserSidebarInteractionState.connected(to: browser) === interaction)
        let space = try XCTUnwrap(browser.selectedSpace)
        let tab = try XCTUnwrap(browser.selectedTab)
        interaction.sidebarReorderState.stage(
            item: .tab(BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)),
            section: .tabs(placement: tab.placement, folderID: nil))

        browser.resetPrivateBrowsingSession()

        XCTAssertFalse(interaction.sidebarReorderState.hasLiftInFlight)
    }

    func testMovingAnotherTabDoesNotRetargetTheCurrentDrag() throws {
        let browser = BrowserStore.preview()
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let source = try XCTUnwrap(browser.session.spaces.first)
        let destination = try XCTUnwrap(browser.session.spaces.last)
        let dragged = try XCTUnwrap(source.currentTabs.first)
        let moved = try XCTUnwrap(source.currentTabs.last)
        XCTAssertNotEqual(dragged.id, moved.id)
        let item = BrowserTabDragItem(tabID: dragged.id, spaceID: source.id, profileID: source.profile.id)
        let token = interaction.tabDragState.begin(item: item, placement: dragged.placement)

        XCTAssertTrue(browser.moveTab(moved.id, from: source.id, into: destination.id))

        XCTAssertEqual(interaction.tabDragState.item, item)
        XCTAssertEqual(interaction.tabDragState.sessionToken, token)
        interaction.cancel()
    }

}
