import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceBrandingTests: XCTestCase {
    func testMovedChoicesKeepTheirKeysAndWaitToBeWritten() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3.5, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        defaults.set(20.0, forKey: BrowserDeviceAppearanceStore.sidebarRevealWidthKey)
        defaults.set(1.2, forKey: BrowserSidebarDensityPreference.scaleKey)
        defaults.set(true, forKey: BrowserSidebarDensityPreference.pinsFillRowKey)
        defaults.set(false, forKey: BrowserFolderAppearancePreference.showsTabCountsKey)

        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(appearance.windowBorderWidth, 3.5)
        XCTAssertTrue(appearance.sidebarOnRight)
        XCTAssertEqual(appearance.sidebarRevealWidth, 20)
        XCTAssertEqual(appearance.tabScale, 1.2)
        XCTAssertTrue(appearance.pinsFillRow)
        XCTAssertFalse(appearance.foldersShowTabCounts)

        // A drag writes nothing until the choices settle: every write to these
        // defaults makes each @AppStorage view over them re-check its value.
        appearance.windowBorderWidth = 0
        appearance.tabs.hoverFill = 0.5
        XCTAssertEqual(defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), 3.5)
        XCTAssertTrue(appearance.isBorderless)

        appearance.saveNow()
        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.windowBorderWidth, 0)
        XCTAssertTrue(restored.isBorderless)
        XCTAssertEqual(restored.tabs.hoverFill, 0.5)
    }

    func testFolderSpacingStartsAtTheUsualSpacingAndSurvivesRelaunch() throws {
        let name = "crest-test-folder-spacing-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        // A device that never chose keeps the spacing folders always had.
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(appearance.foldersSpacing, BrowserLookAndFeelDefaults.foldersSpacing)
        let spacing = appearance.foldersSpacing
        XCTAssertEqual(BrowserSidebarMetrics.folderSpacing(spacing), BrowserSidebarMetrics.containerSpacing)
        XCTAssertEqual(BrowserSidebarMetrics.folderPadding(spacing), BrowserSidebarMetrics.containerPadding)
        XCTAssertEqual(BrowserSidebarMetrics.folderHeaderTrim(spacing), 0)

        let compact = try XCTUnwrap(BrowserAppearancePresets.folderSpacing.first { $0.id == "compact" })
        appearance.foldersSpacing = compact.value
        appearance.saveNow()
        XCTAssertEqual(BrowserDeviceAppearanceStore(defaults: defaults).foldersSpacing, compact.value)

        // A stored value that is no choice the setting offers loads as the default.
        for unknown in [-4.0, 10.0, .nan] {
            defaults.set(unknown, forKey: BrowserFolderAppearancePreference.spacingKey)
            XCTAssertEqual(
                BrowserDeviceAppearanceStore(defaults: defaults).foldersSpacing,
                BrowserLookAndFeelDefaults.foldersSpacing)
        }
    }
}
