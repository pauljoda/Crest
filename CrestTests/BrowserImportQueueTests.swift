import XCTest
@testable import Crest

final class BrowserImportQueueTests: XCTestCase {
    func testArcUsesItsNativeSectionLabelInsteadOfACrestIdentityRow() {
        XCTAssertEqual(BrowserImportApplication.arc.sourceSpaceHeaderStyle, .sectionLabel)
        XCTAssertEqual(BrowserImportApplication.zen.sourceSpaceHeaderStyle, .identity)
        XCTAssertEqual(BrowserImportApplication.chrome.sourceSpaceHeaderStyle, .identity)
        XCTAssertEqual(BrowserImportApplication.safari.sourceSpaceHeaderStyle, .identity)
    }

    func testSelectionUsesDetectedBrowserOrder() {
        let queue = BrowserImportQueue(
            selected: [.safari, .arc, .chrome],
            availableOrder: [.arc, .zen, .chrome, .safari]
        )

        XCTAssertEqual(queue.applications, [.arc, .chrome, .safari])
        XCTAssertEqual(queue.current, .arc)
        XCTAssertEqual(queue.position, 1)
        XCTAssertEqual(queue.count, 3)
    }

    func testAdvanceVisitsEverySelectedBrowserOnce() {
        var queue = BrowserImportQueue(
            applications: [.arc, .zen, .safari]
        )

        XCTAssertEqual(queue.current, .arc)
        XCTAssertEqual(queue.progressLabel, "Browser 1 of 3")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current, .zen)
        XCTAssertEqual(queue.progressLabel, "Browser 2 of 3")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current, .safari)
        XCTAssertEqual(queue.progressLabel, "Browser 3 of 3")
        XCTAssertFalse(queue.advance())
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isComplete)
    }

    func testSingleBrowserQueueDoesNotNeedAProgressLabel() {
        let queue = BrowserImportQueue(applications: [.arc])

        XCTAssertNil(queue.progressLabel)
    }

    func testEmptySelectionHasNoCurrentBrowser() {
        let queue = BrowserImportQueue(
            selected: [],
            availableOrder: [.arc, .zen]
        )

        XCTAssertTrue(queue.applications.isEmpty)
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isComplete)
    }

    func testReviewNavigationAdvancesThroughSpacesBeforeImporting() {
        let spaceIDs = [SpaceID(), SpaceID(), SpaceID()]

        XCTAssertEqual(
            BrowserImportReviewNavigation.nextSpaceID(
                after: spaceIDs[0],
                in: spaceIDs
            ),
            spaceIDs[1]
        )
        XCTAssertEqual(
            BrowserImportReviewNavigation.nextSpaceID(
                after: spaceIDs[1],
                in: spaceIDs
            ),
            spaceIDs[2]
        )
        XCTAssertNil(
            BrowserImportReviewNavigation.nextSpaceID(
                after: spaceIDs[2],
                in: spaceIDs
            )
        )
        XCTAssertTrue(
            BrowserImportReviewNavigation.isFinalSpace(
                spaceIDs[2],
                in: spaceIDs
            )
        )
        XCTAssertFalse(
            BrowserImportReviewNavigation.isFinalSpace(
                spaceIDs[0],
                in: spaceIDs
            )
        )
    }

    func testImportPreviewKeepsOnlyTheTopSidebarControl() {
        XCTAssertNil(BrowserImportPreviewControls.sourceFooterLeadingSymbol)
    }

    func testImportPreviewUsesCalibratedBrandingLanguage() {
        XCTAssertTrue(
            BrowserImportPreviewControls.describesDestinationAsSimplifiedBrandingPreview
        )
    }

    func testBrowserChooserUsesTheAnchoredWizardFooter() {
        XCTAssertTrue(BrowserImportPreviewControls.usesAnchoredImportFooter)
    }
}
