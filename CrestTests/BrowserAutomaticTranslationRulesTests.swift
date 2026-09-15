import XCTest

@testable import Crest

final class BrowserAutomaticTranslationRulesTests: XCTestCase {
    func testOnlyExplicitEnabledSourcesTranslateAndMappingsSurvivePersistence() {
        var rules = BrowserAutomaticTranslationRules()
        XCTAssertNil(rules.target(for: "es"), "Existing automatic mode must not opt every language in.")
        rules.set(sourceID: "es", targetID: "en", isEnabled: true)
        rules.set(sourceID: "de", targetID: "fr", isEnabled: true)
        rules.set(sourceID: "it", targetID: "en", isEnabled: false)
        let restored = BrowserAutomaticTranslationRules(rawValue: rules.rawValue)
        XCTAssertEqual(restored, rules)
        XCTAssertEqual(restored.target(for: "es-MX"), "en")
        XCTAssertEqual(restored.target(for: "de"), "fr")
        XCTAssertNil(restored.target(for: "it"))
        XCTAssertNil(restored.target(for: "ja"))
        XCTAssertEqual(restored.rule(for: "it")?.targetID, "en", "Disabling retains the chosen destination.")
    }

    func testScriptChoicesRemainDistinctAndRegionAliasesCannotBypassDisabling() {
        var rules = BrowserAutomaticTranslationRules()
        rules.set(sourceID: "zh-Hant", targetID: "en", isEnabled: true)
        XCTAssertEqual(rules.target(for: "zh-TW"), "en")
        XCTAssertNil(rules.target(for: "zh-Hans"))
        rules.set(sourceID: "es", targetID: "en", isEnabled: true)
        rules.set(sourceID: "es-MX", targetID: "fr", isEnabled: false)
        XCTAssertNil(rules.target(for: "es"))
        XCTAssertNil(rules.target(for: "es-ES"))
        XCTAssertEqual(rules.sources.count, 2)
    }

    func testMissingCorruptOrSameLanguageRulesCannotTriggerAutomaticTranslation() {
        for rawValue in ["", "invalid", "{}", "{\"sources\":{\"es\":{\"isEnabled\":true}}}"] {
            XCTAssertNil(BrowserAutomaticTranslationRules(rawValue: rawValue).target(for: "es"))
        }
        var rules = BrowserAutomaticTranslationRules()
        rules.set(sourceID: "es", targetID: "", isEnabled: true)
        XCTAssertNil(rules.target(for: "es"))
        rules.set(sourceID: "en-US", targetID: "en-GB", isEnabled: true)
        XCTAssertNil(rules.target(for: "en"))
        rules.set(sourceID: "zh-Hans", targetID: "zh-Hant", isEnabled: true)
        XCTAssertEqual(rules.target(for: "zh-Hans"), "zh-Hant")
    }
}
