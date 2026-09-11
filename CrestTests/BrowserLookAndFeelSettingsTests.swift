import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserLookAndFeelSettingsTests: XCTestCase {
    func testSettingValueReportsAndRestoresItsDefault() {
        var radius = BrowserLookAndFeelDefaults.cornerRadius
        let value = CrestSettingValue(
            Binding(get: { radius }, set: { radius = $0 }),
            default: BrowserLookAndFeelDefaults.cornerRadius
        )
        XCTAssertTrue(value.isDefault)
        XCTAssertFalse([value.resettable("Corner radius")].isModified)

        radius = 24
        XCTAssertFalse(value.isDefault)
        let modified = [value.resettable("Corner radius")]
        XCTAssertTrue(modified.isModified)

        modified.resetAll()
        XCTAssertEqual(radius, BrowserLookAndFeelDefaults.cornerRadius)
        XCTAssertTrue(value.isDefault)

        var accent: BrowserSpaceBrandColor?
        let color = CrestSettingValue(Binding(get: { accent }, set: { accent = $0 }))
        XCTAssertTrue(color.isDefault)
        accent = .indigo
        XCTAssertFalse(color.isDefault)
        color.reset()
        XCTAssertNil(accent)
    }

    func testPaneSplitsOnlyWhereBothColumnsFit() {
        XCTAssertEqual(BrowserLookAndFeelLayoutPolicy.mode(forWidth: 393), .inlinePreviews)
        XCTAssertEqual(
            BrowserLookAndFeelLayoutPolicy.mode(
                forWidth: BrowserLookAndFeelLayoutPolicy.pinnedPreviewMinimumWidth - 1),
            .inlinePreviews)
        XCTAssertEqual(
            BrowserLookAndFeelLayoutPolicy.mode(forWidth: BrowserLookAndFeelLayoutPolicy.pinnedPreviewMinimumWidth),
            .pinnedPreview)

        // The form never grows past the readable width; the preview takes the rest.
        let narrow = BrowserLookAndFeelLayoutPolicy.columns(
            forWidth: BrowserLookAndFeelLayoutPolicy.pinnedPreviewMinimumWidth)
        XCTAssertEqual(narrow.preview, BrowserLookAndFeelLayoutPolicy.previewMinimumWidth)
        XCTAssertEqual(narrow.form, BrowserLookAndFeelLayoutPolicy.formMinimumWidth)
        let wide = BrowserLookAndFeelLayoutPolicy.columns(forWidth: 1400)
        XCTAssertEqual(wide.form, BrowserLookAndFeelLayoutPolicy.formMaximumWidth)
        let expectedPreview =
            1400 - BrowserLookAndFeelLayoutPolicy.previewLeadingPadding
            - BrowserLookAndFeelLayoutPolicy.formMaximumWidth
        XCTAssertEqual(wide.preview, expectedPreview)
        XCTAssertEqual(BrowserLookAndFeelSidebarCrop.sidebarWidth(in: 260), 260 - 72)
        XCTAssertEqual(BrowserLookAndFeelSidebarCrop.sidebarWidth(in: 900), BrowserChromeLayout.sidebarIdealWidth)
    }

    func testPresetsSelectOnlyTheValuesThatReadAsThem() {
        let radius = BrowserAppearancePresets.cornerRadius
        let radiusTolerance = BrowserAppearancePresets.cornerRadiusTolerance
        XCTAssertEqual(BrowserAppearancePresets.match(0, in: radius, tolerance: radiusTolerance)?.id, "square")
        XCTAssertEqual(BrowserAppearancePresets.match(10.4, in: radius, tolerance: radiusTolerance)?.id, "round")
        XCTAssertNil(BrowserAppearancePresets.match(20, in: radius, tolerance: radiusTolerance))
        XCTAssertNil(BrowserAppearancePresets.match(.nan, in: radius, tolerance: radiusTolerance))

        let scale = BrowserAppearancePresets.tabScale
        let scaleTolerance = BrowserAppearancePresets.tabScaleTolerance
        XCTAssertEqual(BrowserAppearancePresets.match(1.02, in: scale, tolerance: scaleTolerance)?.id, "default")
        XCTAssertNil(BrowserAppearancePresets.match(1.05, in: scale, tolerance: scaleTolerance))
    }

    func testFreshStoresStartAtTheDefaultsCatalogAndResetReturnsToIt() throws {
        let suiteName = "crest-tests-look-and-feel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(store.cornerRadius, BrowserLookAndFeelDefaults.cornerRadius)
        XCTAssertEqual(store.tabs, BrowserLookAndFeelDefaults.tabs)
        XCTAssertEqual(store.address, BrowserLookAndFeelDefaults.address)
        XCTAssertEqual(BrowserChromeAppearance().borderWidth, BrowserLookAndFeelDefaults.windowBorderWidth)
        XCTAssertEqual(BrowserChromeAppearance().sidebarOnRight, BrowserLookAndFeelDefaults.sidebarOnRight)

        store.cornerRadius = 32
        store.tabs.pinFill = 0.8
        store.address.border = 0.4
        defaults.set(0, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        defaults.set(1.4, forKey: BrowserSidebarDensityPreference.scaleKey)
        defaults.set(3, forKey: BrowserSidebarDensityPreference.pinColumnsKey)
        defaults.set(true, forKey: BrowserFolderAppearancePreference.alwaysVisibleKey)
        defaults.set(false, forKey: BrowserFolderAppearancePreference.showsTabCountsKey)
        defaults.set(false, forKey: BrowserFolderAppearancePreference.showsBordersKey)

        BrowserLookAndFeelDefaults.resetAll(
            appearance: store, chrome: defaults, density: defaults, folders: defaults)

        XCTAssertEqual(store.cornerRadius, BrowserLookAndFeelDefaults.cornerRadius)
        XCTAssertEqual(store.tabs, BrowserLookAndFeelDefaults.tabs)
        XCTAssertEqual(store.address, BrowserLookAndFeelDefaults.address)
        XCTAssertEqual(
            defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey),
            BrowserLookAndFeelDefaults.windowBorderWidth)
        XCTAssertEqual(
            defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey),
            BrowserLookAndFeelDefaults.sidebarOnRight)
        XCTAssertEqual(
            defaults.double(forKey: BrowserSidebarDensityPreference.scaleKey),
            BrowserLookAndFeelDefaults.tabScale)
        XCTAssertEqual(
            defaults.integer(forKey: BrowserSidebarDensityPreference.pinColumnsKey),
            BrowserLookAndFeelDefaults.pinColumns)
        XCTAssertEqual(
            defaults.bool(forKey: BrowserFolderAppearancePreference.alwaysVisibleKey),
            BrowserLookAndFeelDefaults.foldersAlwaysVisible)
        XCTAssertEqual(
            defaults.bool(forKey: BrowserFolderAppearancePreference.showsTabCountsKey),
            BrowserLookAndFeelDefaults.foldersShowTabCounts)
        XCTAssertEqual(
            defaults.bool(forKey: BrowserFolderAppearancePreference.showsBordersKey),
            BrowserLookAndFeelDefaults.foldersShowBorders)
    }
}
