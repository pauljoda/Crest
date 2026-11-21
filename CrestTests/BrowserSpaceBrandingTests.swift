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

    func testTabChoicesSavedBeforeTheSelectedTabStyleKeepTheirOwnAndTakeTheStandardStyle() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = """
            {"borders":"selected","outlinesSelectedTabs":true,"usesWebsitePinColor":false,"dimsUnloadedTabs":true,
            "pinFill":0,"pinGlow":0,"hoverFill":0,"statusStyle":"badge","showsAudioVisualizer":true}
            """
        defaults.set(Data(saved.utf8), forKey: BrowserDeviceAppearanceStore.tabsKey)

        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertTrue(appearance.tabs.outlinesSelectedTabs)
        XCTAssertFalse(appearance.tabs.usesWebsitePinColor)
        XCTAssertEqual(appearance.tabs.selectedTabStyle, .standard)
        XCTAssertEqual(appearance.tabs.selectedTabOpacity, CrestOpacity.selectedTabPaper)
        XCTAssertTrue(appearance.tabs.tintsSelectedPins)

        appearance.tabs.selectedTabStyle = .material
        appearance.tabs.selectedTabOpacity = 0.5
        appearance.tabs.tintsSelectedPins = false
        appearance.saveNow()
        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.tabs.selectedTabStyle, .material)
        XCTAssertEqual(restored.tabs.selectedTabOpacity, 0.5)
        XCTAssertFalse(restored.tabs.tintsSelectedPins)
    }
}
