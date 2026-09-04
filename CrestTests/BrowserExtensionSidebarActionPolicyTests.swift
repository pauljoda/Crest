import XCTest

@testable import Crest

final class BrowserExtensionSidebarActionPolicyTests: XCTestCase {
    func testToolbarOnlyInterceptsEnabledChromePanelsWithTheBehaviorFlag() {
        XCTAssertTrue(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .action, flavor: .sidePanel, opensOnAction: true, hasPanel: true))
        XCTAssertFalse(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .action, flavor: .sidePanel, opensOnAction: false, hasPanel: true))
        XCTAssertFalse(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .action, flavor: .sidePanel, opensOnAction: true, hasPanel: false))
        XCTAssertFalse(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .action, flavor: .sidebarAction, opensOnAction: true, hasPanel: true))
    }

    func testExplicitMenuAndFirefoxCommandDoNotNeedTheChromeBehaviorFlag() {
        XCTAssertTrue(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .menu, flavor: .sidePanel, opensOnAction: false, hasPanel: true))
        XCTAssertTrue(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .sidebarCommand, flavor: .sidebarAction, opensOnAction: false, hasPanel: true))
        XCTAssertFalse(
            BrowserExtensionSidebarActionPolicy.intercepts(
                .sidebarCommand, flavor: .sidePanel, opensOnAction: true, hasPanel: true))
    }

    func testMenuToggleIsDiscoverableAndUnassignedByDefault() {
        let command = BrowserShortcutCommand.toggleExtensionSidePanel
        XCTAssertEqual(command.section, .view)
        XCTAssertNil(command.defaultShortcut)
        XCTAssertEqual(command.paletteSymbol, "sidebar.trailing")
        XCTAssertTrue(command.matches(search: "extension panel"))
    }
}
