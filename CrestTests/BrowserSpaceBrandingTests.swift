import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceBrandingTests: XCTestCase {
    func testDeviceAppearanceIsExcludedFromSpacePersistence() throws {
        let original = BrowserSpaceBranding(colors: [.indigo, .gold])
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        XCTAssertNil(payload["tabAppearance"])
        XCTAssertNil(payload["addressAppearance"])
        // Ignore the unreleased per-Space prototype's fields when reading a review profile.
        payload["tabAppearance"] = ["pinFill": 0.7]
        payload["addressAppearance"] = ["border": 0.6]
        let restored = try JSONDecoder().decode(
            BrowserSpaceBranding.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(restored, original)
    }

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
        XCTAssertEqual(local.containerCornerRadius(padding: 4), 0)
        local.cornerRadius = 4
        XCTAssertEqual(local.containerCornerRadius(padding: 4), 8)
        local.cornerRadius = 40
        XCTAssertEqual(local.sidebarCornerRadius, 40)
        XCTAssertEqual(local.containerCornerRadius(), 10)
        XCTAssertEqual(local.containerCornerRadius(padding: 4), 14)
        local.cornerRadius = 24
        local.tabs.dimsUnloadedTabs = false
        local.address.border = 0.6
        let restored = BrowserDeviceAppearanceStore(defaults: first)
        XCTAssertEqual(restored.tabs, local.tabs)
        XCTAssertFalse(restored.tabs.dimsUnloadedTabs)
        XCTAssertEqual(restored.cornerRadius, 24)
        XCTAssertEqual(restored.address, local.address)
        let otherDevice = BrowserDeviceAppearanceStore(defaults: second)
        XCTAssertEqual(otherDevice.tabs, .init())
        XCTAssertEqual(otherDevice.cornerRadius, 10)
        XCTAssertEqual(otherDevice.address, .init())
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

        BrowserLookAndFeelDefaults.resetAll(
            appearance: appearance, chrome: defaults, density: defaults, folders: defaults)

        let restored = BrowserDeviceAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.tabs, BrowserLookAndFeelDefaults.tabs)
        XCTAssertTrue(restored.tabs.dimsUnloadedTabs)
        XCTAssertEqual(restored.address, BrowserLookAndFeelDefaults.address)
        XCTAssertEqual(restored.cornerRadius, BrowserLookAndFeelDefaults.cornerRadius)
    }

    // MARK: - Sigils

    // MARK: - The forge

    // MARK: - Rendering version

    func testTheRenderingVersionBumpDoesNotReopenTheBannerStrengthMigration() throws {
        // Version 1 payloads still get their banner strength rescaled; every
        // version at or above the baseline is already stored in today's units.
        let source = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerStrength: 0.4
        )
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
                as? [String: Any]
        )
        legacy["renderingVersion"] = 1
        var expandedEra = legacy
        expandedEra["renderingVersion"] = 3

        let migrated = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        let untouched = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: expandedEra)
        )

        XCTAssertGreaterThan(migrated.bannerStrength, 0.4)
        XCTAssertEqual(untouched.bannerStrength, 0.4)
    }

    // MARK: - Forward tolerance

    func testUnknownCrestVocabularyFallsBackInsteadOfFailingTheWholeDecode() throws {
        // A newer build can name a charge, a shield, or a division this build has
        // never heard of. The Space still has to arrive.
        var branding = try brandingObject(
            BrowserSpaceBranding(
                colors: [.ink, .ocean, .gold],
                iconStyle: .layeredCrest,
                crest: BrowserSpaceCrest(
                    backplate: .seal,
                    fieldDivision: .quarterly,
                    ordinary: .saltire,
                    trim: .laurel,
                    symbol: .oak,
                    chargeLayout: .trio
                )
            )
        )
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        crest["backplate"] = "obelisk"
        crest["fieldDivision"] = "futureDivision"
        crest["ordinary"] = "gyron"
        crest["trim"] = "mantling"
        crest["symbol"] = "basilisk"
        crest["chargeLayout"] = "sevenfold"
        branding["crest"] = crest

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: branding)
        )

        XCTAssertEqual(decoded.crest.backplate, .shield)
        XCTAssertEqual(decoded.crest.fieldDivision, .plain)
        XCTAssertEqual(decoded.crest.ordinary, .none)
        XCTAssertEqual(decoded.crest.trim, .none)
        XCTAssertEqual(decoded.crest.symbol, .mountain)
        XCTAssertEqual(decoded.crest.chargeLayout, .single)
        // Everything the build does understand survives untouched.
        XCTAssertEqual(decoded.colors, [.ink, .ocean, .gold])
        XCTAssertEqual(decoded.iconStyle, .layeredCrest)
    }

    func testUnknownSurfaceVocabularyFallsBackInsteadOfFailingTheWholeDecode() throws {
        var branding = try brandingObject(
            BrowserSpaceBranding(
                colors: [.ink, .ocean, .gold],
                bannerPattern: .chevron,
                themeMode: .gradient,
                iconStyle: .layeredCrest
            )
        )
        branding["bannerPattern"] = "gyronny"
        branding["themeMode"] = "mesh"
        branding["iconStyle"] = "engraving"

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: branding)
        )

        XCTAssertEqual(decoded.bannerPattern, .solid)
        XCTAssertEqual(decoded.themeMode, .banner)
        XCTAssertEqual(decoded.iconStyle, .simpleSymbol)
        XCTAssertEqual(decoded.colors, [.ink, .ocean, .gold])
    }

    func testAWholeSpaceStillArrivesWhenItsBrandingUsesUnknownVocabulary() throws {
        var space = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(BrowserSession.preview.selectedSpace)
            ) as? [String: Any]
        )
        var branding = try XCTUnwrap(space["branding"] as? [String: Any])
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        crest["symbol"] = "futureBeast"
        branding["crest"] = crest
        branding["renderingVersion"] = 99
        space["branding"] = branding

        let decoded = try JSONDecoder().decode(
            BrowserSpace.self,
            from: JSONSerialization.data(withJSONObject: space)
        )

        XCTAssertEqual(decoded.branding.crest.symbol, .mountain)
        XCTAssertFalse(decoded.tabs.isEmpty)
    }

    private func brandingObject(
        _ branding: BrowserSpaceBranding
    ) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(branding))
                as? [String: Any]
        )
    }

    func testRetiredPalettesStillRenderForSpacesThatAlreadyChoseThem() throws {
        // Palettes are templates, not references: the Space stores resolved
        // colors, so retiring a swatch cannot restyle anyone's Space.
        let retired = BrowserSpaceBranding(
            colors: [.ink, .ember, .gold],
            readabilityFade: BrowserSpaceBranding.initialReadabilityFade
        )
        let encoded = try JSONEncoder().encode(retired)
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: encoded
        )

        XCTAssertEqual(decoded.colors, [.ink, .ember, .gold])
        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: decoded),
            .light
        )
        XCTAssertFalse(
            BrowserSpaceBrandingPreset.curated.contains {
                $0.isSelected(in: decoded)
            })
    }

    func testLegacyThemeDefaultsToBannerAndEncodesTheModeExplicitly() throws {
        let source = BrowserSpaceBranding(colors: [.ink, .ocean, .gold])
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
                as? [String: Any]
        )
        object.removeValue(forKey: "themeMode")
        object.removeValue(forKey: "gradientAngle")
        object.removeValue(forKey: "showsTexture")

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
                as? [String: Any]
        )

        XCTAssertEqual(encodedObject["themeMode"] as? String, "banner")
        XCTAssertEqual(encodedObject["gradientAngle"] as? Double, 0)
        XCTAssertEqual(encodedObject["showsTexture"] as? Bool, false)
    }

    func testLegacyBrandingDecodingMigratesReadabilityAndHeraldicDefaults() throws {
        var source = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        source.branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerPattern: .diagonal,
            bannerStrength: 0.4,
            readabilityFade: 0,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .shield,
                fieldDivision: .perPale,
                ordinary: .chief,
                trim: .laurel,
                symbol: .star,
                chargeLayout: .paired,
                backplateColorIndex: 0,
                secondaryFieldColorIndex: 1,
                ordinaryColorIndex: 2,
                trimColorIndex: 2,
                symbolColorIndex: 1
            )
        )
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var branding = try XCTUnwrap(object["branding"] as? [String: Any])
        branding.removeValue(forKey: "readabilityFade")
        branding["sharpness"] = 0.25
        branding["keepsControlsReadable"] = false
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        crest.removeValue(forKey: "fieldDivision")
        crest.removeValue(forKey: "ordinary")
        crest.removeValue(forKey: "chargeLayout")
        crest.removeValue(forKey: "secondaryFieldColorIndex")
        crest.removeValue(forKey: "ordinaryColorIndex")
        branding["crest"] = crest
        object["branding"] = branding

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertEqual(decoded.branding.readabilityFade, 0)
        XCTAssertEqual(decoded.branding.crest.fieldDivision, .plain)
        XCTAssertEqual(decoded.branding.crest.ordinary, .none)
        XCTAssertEqual(decoded.branding.crest.chargeLayout, .single)
        XCTAssertEqual(decoded.branding.crest.secondaryFieldColorIndex, 0)
        XCTAssertEqual(decoded.branding.crest.ordinaryColorIndex, 0)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        let reencodedBranding = try XCTUnwrap(
            reencodedObject["branding"] as? [String: Any]
        )
        XCTAssertNil(reencodedBranding["sharpness"])
    }

    func testLegacySpaceDecodingCreatesACompatibleBrandingIdentity() throws {
        let source = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "branding")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertEqual(decoded.branding, .legacy(accent: source.accent, symbol: source.symbol))
        XCTAssertEqual(decoded.symbol, source.symbol)
        XCTAssertEqual(decoded.accent, source.accent)
    }

    func testUpdatingBrandingChangesOnlyTheTargetSpace() throws {
        var session = BrowserSession.preview
        let target = try XCTUnwrap(session.spaces.first)
        let untouched = try XCTUnwrap(session.spaces.last)
        let untouchedBranding = untouched.branding
        let targetProfileID = target.profile.id
        let untouchedProfileID = untouched.profile.id
        let branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerPattern: .chevron,
            bannerStrength: 0.42,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .shield,
                trim: .laurel,
                symbol: .mountain,
                backplateColorIndex: 1,
                trimColorIndex: 2,
                symbolColorIndex: 0
            )
        )

        session.updateSpaceBranding(branding, in: target.id)

        XCTAssertEqual(session.space(id: target.id)?.branding, branding)
        XCTAssertEqual(session.space(id: untouched.id)?.branding, untouchedBranding)
        XCTAssertEqual(
            session.space(id: target.id)?.profile.id,
            targetProfileID
        )
        XCTAssertEqual(
            session.space(id: untouched.id)?.profile.id,
            untouchedProfileID
        )
    }

    func testBrandingRoundTripsThroughSpaceCoding() throws {
        var source = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        source.branding = BrowserSpaceBranding(
            colors: [.indigo, .sky, .ember],
            bannerPattern: .bands,
            bannerStrength: 0.3,
            readabilityFade: 0.62,
            themeMode: .gradient,
            gradientAngle: 312,
            showsTexture: true,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .seal,
                fieldDivision: .perChevron,
                ordinary: .saltire,
                trim: .doubleRing,
                symbol: .bird,
                chargeLayout: .paired,
                backplateColorIndex: 0,
                secondaryFieldColorIndex: 1,
                ordinaryColorIndex: 2,
                trimColorIndex: 2,
                symbolColorIndex: 1
            )
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: data)

        XCTAssertEqual(decoded.branding, source.branding)
    }
}
