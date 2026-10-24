import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceBrandingTests: XCTestCase {
    func testDeviceAppearancePersistsLocallyAndToleratesUnknownFields() throws {
        let firstName = "crest-test-appearance-" + UUID().uuidString
        let secondName = "crest-test-appearance-" + UUID().uuidString
        let first = try XCTUnwrap(UserDefaults(suiteName: firstName))
        let second = try XCTUnwrap(UserDefaults(suiteName: secondName))
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }
        first.set(
            try JSONSerialization.data(withJSONObject: [
                "borders": "future", "pinFill": 0.7, "hoverFill": 4, "cornerRadius": 0,
            ]),
            forKey: BrowserDeviceAppearanceStore.tabsKey)
        let local = BrowserDeviceAppearanceStore(defaults: first)
        XCTAssertEqual(local.tabs.borders, .selected)
        XCTAssertTrue(local.tabs.dimsUnloadedTabs)
        XCTAssertEqual(local.tabs.pinFill, 0.7)
        XCTAssertEqual(local.tabs.hoverFill, 1)
        XCTAssertEqual(local.cornerRadius, 0)
        XCTAssertEqual(BrowserSidebarMetrics.layerCornerRadius(depth: 0, userRadius: local.sidebarCornerRadius), 0)
        local.cornerRadius = 4
        XCTAssertEqual(BrowserSidebarMetrics.layerCornerRadius(depth: 0, userRadius: local.sidebarCornerRadius), 8)
        local.cornerRadius = 40
        XCTAssertEqual(local.sidebarCornerRadius, 40)
        XCTAssertEqual(BrowserSidebarMetrics.layerCornerRadius(depth: 1, userRadius: local.sidebarCornerRadius), 10)
        XCTAssertEqual(BrowserSidebarMetrics.layerCornerRadius(depth: 0, userRadius: local.sidebarCornerRadius), 14)
        local.cornerRadius = 24
        local.tabs.dimsUnloadedTabs = false
        local.address.border = 0.6
        local.saveNow()
        let restored = BrowserDeviceAppearanceStore(defaults: first)
        XCTAssertEqual(try saved(restored.tabs), try saved(local.tabs))
        XCTAssertFalse(restored.tabs.dimsUnloadedTabs)
        XCTAssertEqual(restored.cornerRadius, 24)
        XCTAssertEqual(try saved(restored.address), try saved(local.address))
        let otherDevice = BrowserDeviceAppearanceStore(defaults: second)
        XCTAssertEqual(try saved(otherDevice.tabs), try saved(BrowserTabAppearance()))
        XCTAssertEqual(otherDevice.cornerRadius, 10)
        XCTAssertEqual(try saved(otherDevice.address), try saved(BrowserAddressAppearance()))
    }

    func testResetAllLookAndFeelPersistsDefaultDeviceAppearance() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        appearance.tabs.dimsUnloadedTabs = false
        appearance.tabs.pinFill = 0.7
        appearance.address.border = 0.6
        appearance.cornerRadius = 24

        BrowserLookAndFeelDefaults.resetAll(appearance: appearance)

        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(try saved(restored.tabs), try saved(BrowserLookAndFeelDefaults.tabs))
        XCTAssertTrue(restored.tabs.dimsUnloadedTabs)
        XCTAssertEqual(try saved(restored.address), try saved(BrowserLookAndFeelDefaults.address))
        XCTAssertEqual(restored.cornerRadius, BrowserLookAndFeelDefaults.cornerRadius)
    }

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

    /// The saved form of an appearance model, which is how two of them compare.
    private func saved(_ appearance: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(appearance)
    }
}
