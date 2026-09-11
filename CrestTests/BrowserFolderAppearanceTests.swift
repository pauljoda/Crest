import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFolderAppearanceTests: XCTestCase {
    func testFolderSymbolMutationRejectsStaleOwnershipAndSurvivesSync() throws {
        var first = BrowserSession.makeBlankSpace(number: 1)
        let folder = BrowserFolder(title: "Reading")
        first.folders = [folder]
        first.tabs[0].iconMode = .automatic
        var second = BrowserSession.makeBlankSpace(number: 2)
        second.tabs[0].iconMode = .automatic
        let session = BrowserSession(spaces: [first, second], selectedSpaceID: first.id)
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let emoji = BrowserIconSymbol.symbol(forEmoji: "📚")
        let stale = BrowserSpaceRuntimeAssignment(spaceID: first.id, profileID: UUID())
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: stale, symbol: emoji))
        XCTAssertEqual(browser.session, session)
        XCTAssertTrue(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        var journal = BrowserSyncJournal(deviceID: UUID())
        try journal.stage(session: restored, at: Date())
        let synced = try journal.materializedSession(applyingTo: session)
        XCTAssertEqual(synced.space(id: first.id)?.folders.first?.symbol, emoji)
        XCTAssertEqual(synced.space(id: first.id)?.tabs, first.tabs)
        XCTAssertEqual(synced.space(id: second.id), second)
    }

    func testIntensityBindingPersistsOnlyItsSpaceAndSyncsInExistingBranding() throws {
        let first = BrowserSession.makeBlankSpace(number: 1)
        let second = BrowserSession.makeBlankSpace(number: 2)
        let session = BrowserSession(spaces: [first, second], selectedSpaceID: first.id)
        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(session: session, persistence: persistence)
        let binding = browser.spaceBrandingBinding(in: first).folderColorIntensity
        binding.wrappedValue = 0.75
        browser.spaceBrandingBinding(in: first).textColorMode.wrappedValue = .light
        XCTAssertEqual(browser.session.space(id: first.id)?.branding.folderColorIntensity, 0.75)
        XCTAssertEqual(browser.session.space(id: second.id), second)
        XCTAssertEqual(browser.session.space(id: first.id)?.folders, first.folders)
        XCTAssertEqual(browser.session.space(id: first.id)?.tabs, first.tabs)
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        XCTAssertEqual(restored.space(id: first.id)?.branding.folderColorIntensity, 0.75)
        XCTAssertEqual(restored.space(id: first.id)?.branding.textColorMode, .light)
        var journal = BrowserSyncJournal(deviceID: UUID())
        try journal.stage(session: restored, at: Date())
        let synced = try journal.materializedSession(applyingTo: session)
        XCTAssertEqual(synced.space(id: first.id)?.branding.folderColorIntensity, 0.75)
        XCTAssertEqual(synced.space(id: second.id)?.branding.folderColorIntensity, 0)
        XCTAssertEqual(synced.space(id: first.id)?.branding.textColorMode, .light)
        XCTAssertEqual(synced.space(id: second.id)?.branding.textColorMode, .automatic)
    }

    func testTextColorOverridesBothContrastingPalettesAndReturnsToAutomatic() throws {
        for color in [BrowserSpaceBrandColor.ink, .gold] {
            var branding = BrowserSpaceBranding(colors: [color], readabilityFade: 0)
            let automatic = BrowserSpaceForegroundPolicy.tone(for: branding)
            for mode in BrowserSpaceTextColorMode.allCases {
                branding.textColorMode = mode
                let restored = try JSONDecoder().decode(
                    BrowserSpaceBranding.self, from: JSONEncoder().encode(branding))
                XCTAssertEqual(restored.normalized().textColorMode, mode)
                XCTAssertEqual(BrowserSpaceForegroundPolicy.tone(for: restored), mode.foregroundTone ?? automatic)
            }
            branding.textColorMode = .automatic
            XCTAssertEqual(BrowserSpaceForegroundPolicy.tone(for: branding), automatic)
        }
    }

    func testMissingAndFutureTextColorChoicesUseAutomatic() throws {
        let branding = BrowserSpaceBranding(colors: [.ink])
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(branding)) as? [String: Any])
        for value in [nil, "future-mode"] as [String?] {
            payload["textColorMode"] = value
            let restored = try JSONDecoder().decode(
                BrowserSpaceBranding.self, from: JSONSerialization.data(withJSONObject: payload))
            XCTAssertEqual(restored.textColorMode, .automatic)
            XCTAssertEqual(
                BrowserSpaceForegroundPolicy.tone(for: restored), BrowserSpaceForegroundPolicy.tone(for: branding))
        }
    }

    func testGlobalChoicesShareDefaultsAndDoNotEnterSpacePayloads() throws {
        let suite = "crest-tests-app315-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visible = AppStorage(
            wrappedValue: false, BrowserFolderAppearancePreference.alwaysVisibleKey, store: defaults)
        let counts = AppStorage(
            wrappedValue: true, BrowserFolderAppearancePreference.showsTabCountsKey, store: defaults)
        let borders = AppStorage(wrappedValue: true, BrowserFolderAppearancePreference.showsBordersKey, store: defaults)
        XCTAssertFalse(visible.wrappedValue)
        XCTAssertTrue(counts.wrappedValue)
        XCTAssertTrue(borders.wrappedValue)
        let session = BrowserSession.preview
        let before = try JSONEncoder().encode(session)
        visible.wrappedValue = true
        counts.wrappedValue = false
        borders.wrappedValue = false
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(reopened.bool(forKey: BrowserFolderAppearancePreference.alwaysVisibleKey))
        XCTAssertFalse(reopened.bool(forKey: BrowserFolderAppearancePreference.showsTabCountsKey))
        XCTAssertFalse(reopened.bool(forKey: BrowserFolderAppearancePreference.showsBordersKey))
        XCTAssertEqual(try JSONDecoder().decode(BrowserSession.self, from: before), session)
    }

    func testLegacyBrandingRetainsSubtleFolderColorAndRoundTripsIntensity() throws {
        let original = BrowserSpaceBranding.legacy(accent: .indigo, symbol: "folder")
        XCTAssertEqual(original.folderColorIntensity, 0)
        var stronger = original
        stronger.folderColorIntensity = 1
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self, from: JSONEncoder().encode(stronger))
        XCTAssertEqual(decoded.folderColorIntensity, 1)
        XCTAssertEqual(decoded.normalized().folderColorIntensity, 1)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(stronger)) as? [String: Any])
        legacy.removeValue(forKey: "folderColorIntensity")
        let restored = try JSONDecoder().decode(
            BrowserSpaceBranding.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.folderColorIntensity, 0)
        XCTAssertEqual(restored.colors, original.colors)
        XCTAssertEqual(restored.renderingVersion, original.renderingVersion)
    }

    func testColorStrengthKeepsExistingEndpointsAndClampsInvalidValues() {
        XCTAssertEqual(BrowserFolderAppearancePolicy.fillOpacity(intensity: 0, reduceTransparency: false), 0.12)
        XCTAssertEqual(BrowserFolderAppearancePolicy.fillOpacity(intensity: 0, reduceTransparency: true), 0.28)
        XCTAssertEqual(BrowserFolderAppearancePolicy.fillOpacity(intensity: 1, reduceTransparency: false), 1)
        XCTAssertEqual(BrowserFolderAppearancePolicy.fillOpacity(intensity: 2, reduceTransparency: false), 1)
        XCTAssertEqual(BrowserFolderAppearancePolicy.fillOpacity(intensity: .nan, reduceTransparency: false), 0.12)
    }

    func testPersistentHighlightsDoNotReplaceInteractionFeedback() {
        XCTAssertFalse(
            BrowserFolderAppearancePolicy.showsFill(alwaysVisible: false, isHovered: false, isTargeted: false))
        XCTAssertTrue(BrowserFolderAppearancePolicy.showsFill(alwaysVisible: true, isHovered: false, isTargeted: false))
        XCTAssertTrue(BrowserFolderAppearancePolicy.showsFill(alwaysVisible: false, isHovered: true, isTargeted: false))
        XCTAssertTrue(BrowserFolderAppearancePolicy.showsFill(alwaysVisible: false, isHovered: false, isTargeted: true))
        XCTAssertGreaterThan(BrowserFolderAppearancePolicy.regionInset, 0)
        XCTAssertEqual(BrowserFolderLayout.contentsInset, 6)
        XCTAssertEqual(BrowserFolderLayout.rowLeadingInset(depth: 0), BrowserFolderLayout.contentsInset)
        XCTAssertEqual(BrowserFolderLayout.rowLeadingInset(depth: 1), 2 * BrowserFolderLayout.contentsInset)
    }

    func testTextToneUsesTheCompositedColorAtIntermediateIntensity() {
        let black = BrowserSpaceBrandColor(red: 0, green: 0, blue: 0)
        let medium = BrowserFolderAppearancePolicy.compositedColor(
            .folderDefault,
            opacity: BrowserFolderAppearancePolicy.fillOpacity(intensity: 0.5, reduceTransparency: false),
            background: black)
        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: .init(colors: [medium], readabilityFade: 0)), .light)
        let opaque = BrowserFolderAppearancePolicy.compositedColor(.gold, opacity: 1, background: black)
        XCTAssertEqual(opaque, .gold)
        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: .init(colors: [opaque], readabilityFade: 0)), .dark)
    }
}
