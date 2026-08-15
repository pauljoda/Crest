import XCTest

@testable import Crest

final class BrowserPagePresentationTests: XCTestCase {
    func testPresentationCasesRemainExhaustive() {
        XCTAssertEqual(
            BrowserPagePresentation.allCases,
            [
                .noSelection,
                .startPage,
                .livePage,
                .navigationFailure,
                .processFailure,
                .unloaded,
                .automaticRestore,
            ]
        )
    }

    func testSelectionStateOutranksResidentPageState() {
        XCTAssertEqual(
            presentation(
                selection: .none,
                hasActivePage: true,
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .noSelection
        )
        XCTAssertEqual(
            presentation(
                selection: .startPage,
                hasActivePage: true,
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .startPage
        )
    }

    func testFailurePrecedenceMatchesTheExistingPageSurfaces() {
        XCTAssertEqual(
            presentation(
                hasActivePage: true,
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .navigationFailure
        )
        XCTAssertEqual(
            presentation(
                hasActivePage: true,
                hasProcessFailure: true
            ),
            .processFailure
        )
        XCTAssertEqual(
            presentation(hasActivePage: true),
            .livePage
        )
    }

    func testFailuresCannotPresentWithoutTheSelectedResidentPage() {
        XCTAssertEqual(
            presentation(
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .unloaded
        )
    }

    func testMacUnloadedPresentationDoesNotCreateOrRestoreAPage() {
        XCTAssertEqual(presentation(), .unloaded)
    }

    private func presentation(
        selection: BrowserPagePresentationSelection = .webPage,
        hasActivePage: Bool = false,
        hasNavigationFailure: Bool = false,
        hasProcessFailure: Bool = false,
        unloadedBehavior: BrowserPageUnloadedBehavior = .remainUnloaded
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: selection,
                hasActivePage: hasActivePage,
                hasNavigationFailure: hasNavigationFailure,
                hasProcessFailure: hasProcessFailure,
                unloadedBehavior: unloadedBehavior
            )
        )
    }
}
