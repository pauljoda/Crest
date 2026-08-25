import XCTest

@testable import CrestMobile

final class MobileBrowserSidebarWidgetPolicyTests: XCTestCase {
    func testMobileWidgetDeckDragTracksTheVerticalStack() {
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.currentPlatformAxis,
            .vertical
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.primaryTranslation(
                horizontal: 40,
                vertical: -70,
                axis: .vertical
            ),
            -70
        )
        XCTAssertEqual(
            BrowserSidebarWidgetDeckGesturePolicy.cardOffset(
                trackedTranslation: -12,
                slotOffset: 6,
                axis: .vertical
            ),
            CGSize(width: 0, height: -6)
        )
    }

    func testWidgetHostRendersInDockedAndFloatingSidebars() {
        XCTAssertTrue(
            BrowserSidebarWidgetHostPolicy.shouldRender(
                sidebarIsPresented: BrowserSidebarPresentation.docked.showsSidebar,
                isPrivateBrowsing: false
            )
        )
        XCTAssertTrue(
            BrowserSidebarWidgetHostPolicy.shouldRender(
                sidebarIsPresented:
                    BrowserSidebarPresentation.floating.showsSidebar,
                isPrivateBrowsing: false
            )
        )
    }

    func testWidgetHostIsAbsentWhenTheSidebarIsCollapsed() {
        XCTAssertFalse(
            BrowserSidebarWidgetHostPolicy.shouldRender(
                sidebarIsPresented:
                    BrowserSidebarPresentation.collapsed.showsSidebar,
                isPrivateBrowsing: false
            ),
            "A collapsed sidebar has no visible surface for the widget host."
        )
    }

    func testPrivateBrowsingNeverRendersProfileWidgets() {
        XCTAssertFalse(
            BrowserSidebarWidgetHostPolicy.shouldRender(
                sidebarIsPresented: true,
                isPrivateBrowsing: true
            )
        )
    }

    func testDirectDistributionUpdateWidgetIsFilteredFromMobile() {
        let registry = BrowserSidebarWidgetRegistry(
            registrations: [.softwareUpdate]
        )
        XCTAssertFalse(
            registry.supports(
                .softwareUpdate,
                platform: .mobile,
                capabilities: [.persistentSidebar, .directSoftwareUpdates]
            )
        )
    }
}
