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

    func testCustomizationStyleStartsHeraldicAndKeepsEachChoice() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        // A device whose appearance an earlier build stored has no style.
        defaults.set(1.2, forKey: BrowserSidebarDensityPreference.scaleKey)
        let earlier = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(earlier.customizationStyle, .heraldic)
        XCTAssertNil(earlier.chosenSpaceIcons)
        XCTAssertEqual(earlier.spaceIcons, .icons)

        let space = UUID()
        earlier.customizationStyle = .simple
        earlier.setCustomizationStyle(.modern, for: space)
        earlier.saveNow()
        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.customizationStyle, .simple)
        XCTAssertEqual(restored.spaceIcons, .dots)
        XCTAssertEqual(restored.customizationStyle(for: space), .modern)
        XCTAssertEqual(restored.customizationStyle(for: UUID()), .simple)
        XCTAssertEqual(restored.tabScale, 1.2)

        // Space icons the person chose outlast the style, and a Space set
        // back to the style every Space shows follows it again.
        restored.chosenSpaceIcons = .icons
        restored.setCustomizationStyle(.simple, for: space)
        restored.saveNow()
        let chosen = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(chosen.spaceIcons, .icons)
        XCTAssertFalse(chosen.hasOwnCustomizationStyle(space))
    }

    func testASpaceGetsBackTheLookItWoreInAStyle() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let space = UUID()
        let heraldic = SpaceHouse.lion.look.normalized()

        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        let simple = appearance.look(of: space, wearing: heraldic, movingFrom: .heraldic, to: .simple)
        XCTAssertNotEqual(simple, heraldic)
        appearance.saveNow()

        // After a relaunch, going back gives the Space the very look it left.
        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.look(of: space, wearing: simple, movingFrom: .simple, to: .heraldic), heraldic)
    }

    func testRememberedLooksSurviveAnUpdateThatChangesHowLooksAreWritten() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let space = UUID()
        let heraldic = SpaceHouse.lion.look.normalized()
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        let simple = appearance.look(of: space, wearing: heraldic, movingFrom: .heraldic, to: .simple)
        appearance.saveNow()

        // A later build may write a look with a member this one doesn't know;
        // the look it kept still comes back whole.
        var stored = try XCTUnwrap(
            defaults.dictionary(forKey: BrowserDeviceAppearanceStore.rememberedLooksKey) as? [String: [String: String]])
        let text = try XCTUnwrap(stored[space.uuidString]?["heraldic"])
        var form = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        form["memberFromALaterBuild"] = true
        stored[space.uuidString]?["heraldic"] = String(
            decoding: try JSONSerialization.data(withJSONObject: form), as: UTF8.self)
        defaults.set(stored, forKey: BrowserDeviceAppearanceStore.rememberedLooksKey)

        let updated = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(updated.look(of: space, wearing: simple, movingFrom: .simple, to: .heraldic), heraldic)
    }

    func testALookFromAnotherStyleIsNotRememberedAsThisOne() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let space = UUID()
        // Another device restyled the Space to Simple while this one still
        // shows Heraldic (Full).
        let arrived = BrowserCustomizationStyle.simple.look(for: SpaceHouse.lion.look, remembered: nil)
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        let modern = appearance.look(of: space, wearing: arrived, movingFrom: .heraldic, to: .modern)

        // Going back does not give back the Simple look as a Heraldic one.
        let back = appearance.look(of: space, wearing: modern, movingFrom: .modern, to: .heraldic)
        XCTAssertNotEqual(back, arrived)
        XCTAssertEqual(back.iconStyle, .layeredCrest)
    }

    func testAOneColorModernLookIsRememberedAsModern() throws {
        let name = "crest-test-appearance-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let space = UUID()
        let appearance = BrowserDeviceAppearanceStore(defaults: defaults)
        var edited = BrowserCustomizationStyle.modern.look(for: SpaceBranding.neutral, remembered: nil)
        edited.bannerStrength = 0.6

        let simple = appearance.look(of: space, wearing: edited, movingFrom: .modern, to: .simple)
        XCTAssertEqual(appearance.look(of: space, wearing: simple, movingFrom: .simple, to: .modern), edited)
    }

}
