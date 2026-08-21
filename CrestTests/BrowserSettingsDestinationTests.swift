import XCTest

@testable import Crest

final class BrowserSettingsDestinationTests: XCTestCase {
    // MARK: - Identifier contract

    func testRawValuesPinTheAccessibilityIdentifierContract() {
        XCTAssertEqual(
            BrowserSettingsDestination.allCases.map(\.rawValue),
            [
                "general",
                "links",
                "shortcuts",
                "spaces",
                "sync",
                "privacy",
                "passwords",
                "extensions",
                "featureFlags",
                "advanced",
            ],
            """
            Settings identifiers derive from these raw values \
            (settings-<rawValue>, settings-header-<rawValue>, \
            settings-form-<rawValue>). Changing one breaks the automation \
            suites on both platforms.
            """
        )
    }

    func testIdentityMatchesRawValue() {
        for destination in BrowserSettingsDestination.allCases {
            XCTAssertEqual(destination.id, destination.rawValue)
        }
    }

    // MARK: - Ordering

    func testCatalogOrderIsStable() {
        XCTAssertEqual(
            BrowserSettingsDestination.allCases,
            [
                .general,
                .links,
                .shortcuts,
                .spaces,
                .sync,
                .privacy,
                .passwords,
                .extensions,
                .featureFlags,
                .advanced,
            ]
        )
    }

    func testPlatformCasesPreserveCatalogOrder() {
        let platformCases = BrowserSettingsDestination.platformCases
        let expected = BrowserSettingsDestination.allCases
            .filter(platformCases.contains)
        XCTAssertEqual(platformCases, expected)
    }

    // MARK: - Platform capability

    func testShortcutsIsTheOnlyPlatformGatedDestination() {
        for destination in BrowserSettingsDestination.allCases
        where destination != .shortcuts {
            XCTAssertTrue(
                destination.isAvailableOnCurrentPlatform,
                "\(destination.rawValue) must exist on every platform"
            )
        }
    }

    func testDesktopPresentsKeyboardShortcuts() {
        XCTAssertTrue(BrowserSettingsDestination.shortcuts.isAvailableOnCurrentPlatform)
        XCTAssertEqual(
            BrowserSettingsDestination.platformCases,
            BrowserSettingsDestination.allCases
        )
        XCTAssertEqual(BrowserSettingsDestination.platformCases.count, 10)
    }

}
