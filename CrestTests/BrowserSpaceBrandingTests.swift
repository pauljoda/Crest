import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceBrandingTests: XCTestCase {
    func testGradientControlsSupportKeyboardAndSemanticFineTuningLabels() {
        XCTAssertTrue(BrowserSpaceBrandingControlPolicy.gradientDialAcceptsKeyboardFocus)
        XCTAssertTrue(BrowserSpaceBrandingControlPolicy.gradientDialShowsFocusIndicator)
        XCTAssertTrue(BrowserSpaceBrandingControlPolicy.fineTuningSlidersExposeLabels)
        XCTAssertEqual(BrowserSpaceBrandingControlPolicy.gradientAngleStep, 15)
        XCTAssertEqual(
            BrowserSpaceBrandingControlPolicy.adjustedAngle(
                355,
                direction: .increment
            ),
            10
        )
        XCTAssertEqual(
            BrowserSpaceBrandingControlPolicy.adjustedAngle(
                5,
                direction: .decrement
            ),
            350
        )
    }

    func testCuratedPalettesOfferTheNineHouseStartingPoints() {
        XCTAssertEqual(
            BrowserSpaceBrandingPreset.curated.map(\.title),
            [
                "Winter",
                "Lion",
                "Storm",
                "Dragon",
                "Meadow",
                "Iron",
                "River",
                "Sun",
                "Vigil",
            ]
        )
        XCTAssertEqual(
            BrowserSpaceBrandingPreset.curated.map(\.colors),
            BrowserSpaceHousePalette.allCases.map(\.colors)
        )
        XCTAssertTrue(
            BrowserSpaceBrandingPreset.curated.allSatisfy {
                (2...BrowserSpaceBranding.maximumColorCount).contains($0.colors.count)
            })
        XCTAssertEqual(
            Set(BrowserSpaceBrandingPreset.curated.map(\.id)).count,
            BrowserSpaceBrandingPreset.curated.count
        )
    }

    // MARK: - Sigils

    func testEveryCrestChargeResolvesARealSystemSymbol() {
        // A charge whose SF Symbol name is wrong renders as an empty box at every
        // size, in the sidebar and the tab bar, with nothing to catch it at build
        // time. This is the only guard.
        for symbol in BrowserSpaceCrestSymbol.allCases {
            XCTAssertNotNil(
                NSImage(
                    systemSymbolName: symbol.systemImage,
                    accessibilityDescription: nil
                ),
                "\(symbol.rawValue) points at the missing symbol \(symbol.systemImage)."
            )
        }
    }

    func testEveryCrestOrdinaryStillRendersThroughItsDedicatedComponent() {
        for ordinary in BrowserSpaceCrestOrdinary.allCases {
            let renderer = ImageRenderer(
                content: BrowserSpaceCrestOrdinaryView(
                    ordinary: ordinary,
                    backplateSymbol: "shield.fill",
                    outlineSystemImage: "shield",
                    color: BrowserSpaceBrandColor.lionGold.color,
                    size: 112
                )
                .frame(width: 112, height: 112)
            )

            XCTAssertNotNil(renderer.nsImage, "Failed to render \(ordinary.rawValue).")
        }
    }

    func testExtractedCrestOrdinaryComponentsPreserveShippedGeometry() throws {
        let pale = try XCTUnwrap(BrowserSpaceCrestOrdinary.pale.barRendering)
        XCTAssertEqual(pale.widthFactor, 0.18)
        XCTAssertNil(pale.heightFactor)
        XCTAssertEqual(pale.rotationDegrees, 0)

        let fess = try XCTUnwrap(BrowserSpaceCrestOrdinary.fess.barRendering)
        XCTAssertNil(fess.widthFactor)
        XCTAssertEqual(fess.heightFactor, 0.17)
        XCTAssertEqual(fess.rotationDegrees, 0)

        let bend = try XCTUnwrap(BrowserSpaceCrestOrdinary.bend.barRendering)
        XCTAssertEqual(bend.widthFactor, 1.1)
        XCTAssertEqual(bend.heightFactor, 0.17)
        XCTAssertEqual(bend.rotationDegrees, -38)

        let chevron = try XCTUnwrap(BrowserSpaceCrestOrdinary.chevron.symbolRendering)
        XCTAssertEqual(chevron.systemImage, "chevron.up")
        XCTAssertEqual(chevron.sizeFactor, 0.46)
        XCTAssertEqual(chevron.verticalOffsetFactor, 0.07)

        let cross = try XCTUnwrap(BrowserSpaceCrestOrdinary.cross.symbolRendering)
        XCTAssertEqual(cross.systemImage, "plus")
        XCTAssertEqual(cross.sizeFactor, 0.48)
        XCTAssertEqual(cross.verticalOffsetFactor, 0)

        let saltire = try XCTUnwrap(BrowserSpaceCrestOrdinary.saltire.symbolRendering)
        XCTAssertEqual(saltire.systemImage, "xmark")
        XCTAssertEqual(saltire.sizeFactor, 0.48)
        XCTAssertEqual(saltire.verticalOffsetFactor, 0)
    }

    func testExpandedChargesJoinTheClassicSigilsWithoutDisplacingThem() {
        let classics: Set<String> = [
            "sun", "fern", "leaf", "mountain", "compass", "book", "key", "bee",
            "crescent", "waves", "flame", "star", "oak", "tree", "bird", "hare",
            "fish", "shell", "sailboat", "hammer", "tower", "lightning", "sparkles",
        ]
        let expanded: Set<String> = [
            "paw", "hound", "crown", "risingSun", "crossedBanners", "flower",
            "drop", "snowflake", "horn",
        ]
        let shipped = Set(BrowserSpaceCrestSymbol.allCases.map(\.rawValue))

        // Raw values are the on-disk and on-CloudKit spelling of a charge.
        // Renaming one silently restyles every Space that chose it.
        XCTAssertTrue(classics.isSubset(of: shipped))
        XCTAssertTrue(expanded.isSubset(of: shipped))
        XCTAssertEqual(shipped, classics.union(expanded))
        XCTAssertEqual(
            BrowserSpaceCrestSymbol.allCases.count,
            shipped.count,
            "Two charges share a raw value."
        )
    }

    func testEveryChargeIsNamedForTheGalleryCardThatShowsIt() {
        for symbol in BrowserSpaceCrestSymbol.allCases {
            XCTAssertFalse(symbol.title.isEmpty)
        }
        XCTAssertEqual(
            Set(BrowserSpaceCrestSymbol.allCases.map(\.title)).count,
            BrowserSpaceCrestSymbol.allCases.count,
            "Two charges answer to the same name in the gallery."
        )
    }

    // MARK: - The forge

    func testTheForgeOrdersItsStepsTheWayArmsAreComposed() {
        XCTAssertEqual(
            BrowserSpaceForgeStep.allCases,
            [.field, .pattern, .mark, .shield, .division, .ordinary, .charge, .trim]
        )
        XCTAssertEqual(
            BrowserSpaceForgeStep.allCases.filter(\.isCrestStep),
            BrowserSpaceForgeStep.crestSteps
        )
        XCTAssertEqual(
            BrowserSpaceForgeStep.allCases.map(\.accessibilityIdentifier),
            [
                "space-forge-field",
                "space-forge-pattern",
                "space-forge-mark",
                "space-forge-shield",
                "space-forge-division",
                "space-forge-ordinary",
                "space-forge-charge",
                "space-forge-trim",
            ]
        )
        XCTAssertEqual(
            Set(BrowserSpaceForgeStep.allCases.map(\.title)).count,
            BrowserSpaceForgeStep.allCases.count
        )
    }

    func testDefaultCrestFieldContrastsWithTheBannerBackground() {
        let crest = BrowserSpaceCrest()

        XCTAssertEqual(
            crest.backplateColorIndex,
            BrowserSpaceBrandColorRole.primary.rawValue
        )
        XCTAssertNotEqual(
            crest.backplateColorIndex,
            BrowserSpaceBrandColorRole.background.rawValue
        )
    }

    func testTheChargeGalleryNeverShowsTwoCardsThatDrawTheSameFigure() {
        let drawn = BrowserSpaceCrestSymbol.selectable.map(\.systemImage)

        XCTAssertEqual(
            Set(drawn).count,
            drawn.count,
            "Two selectable charges render identically: " + drawn.sorted().joined(separator: ", ")
        )
        // A charge dropped from the gallery must still decode and render, or the
        // Spaces that already wear it would lose their mark.
        XCTAssertFalse(BrowserSpaceCrestSymbol.selectable.contains(.oak))
        XCTAssertTrue(BrowserSpaceCrestSymbol.allCases.contains(.oak))
        XCTAssertEqual(
            BrowserSpaceCrestSymbol.selectable.count,
            BrowserSpaceCrestSymbol.allCases.count - 1
        )
    }

    func testTheForgeComposesAtEveryCallSiteAndBothWidths() {
        var branding = BrowserSpaceBranding(
            colors: BrowserSpaceHousePalette.lion.colors,
            bannerPattern: .quartered,
            readabilityFade: BrowserSpaceBranding.initialReadabilityFade,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(symbol: .crown, symbolColorIndex: 2)
        )
        var symbol = "briefcase.fill"
        let brandingBinding = Binding(get: { branding }, set: { branding = $0 })
        let symbolBinding = Binding(get: { symbol }, set: { symbol = $0 })

        for compact in [false, true] {
            for showsPreview in [false, true] {
                XCTAssertNotNil(
                    BrowserSpaceBrandingEditor(
                        branding: brandingBinding,
                        symbol: symbolBinding,
                        compact: compact,
                        showsPreview: showsPreview
                    ).body
                )
            }
        }

        // The simple-symbol path hides the crest steps but must still compose.
        branding.iconStyle = .simpleSymbol
        XCTAssertNotNil(
            BrowserSpaceBrandingEditor(
                branding: brandingBinding,
                symbol: symbolBinding
            ).body
        )
    }

    func testEditorMutationsNormalizeTheCompleteBrandingValue() {
        var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
        let binding = Binding(get: { branding }, set: { branding = $0 })

        binding.editorUpdate { candidate in
            candidate.bannerStrength = 8
            candidate.gradientAngle = -45
            candidate.crest.symbolColorIndex = 99
        }

        XCTAssertEqual(branding.bannerStrength, 1)
        XCTAssertEqual(branding.gradientAngle, 315)
        XCTAssertEqual(branding.crest.symbolColorIndex, 0)
    }

    func testEditorPreviewNormalizesWithoutMutatingTheLiveBinding() {
        var branding = BrowserSpaceBrandingPreviewFixture.gradientBranding
        let original = branding
        let binding = Binding(get: { branding }, set: { branding = $0 })

        let preview = binding.editorPreview { candidate in
            candidate.bannerStrength = -4
            candidate.crest.trimColorIndex = 99
        }

        XCTAssertEqual(branding, original)
        XCTAssertEqual(preview.iconStyle, .layeredCrest)
        XCTAssertEqual(preview.bannerStrength, 0)
        XCTAssertEqual(preview.crest.trimColorIndex, 0)
    }

    func testEditorPaletteAddsAndRemovesOnlyTheTrailingRole() {
        var branding = BrowserSpaceBranding(
            colors: [.ink, .ocean],
            iconStyle: .layeredCrest
        )
        let binding = Binding(get: { branding }, set: { branding = $0 })

        binding.editorAddColor(for: .primary)
        XCTAssertEqual(branding.colors, [.ink, .ocean])

        binding.editorAddColor(for: .secondary)
        XCTAssertEqual(branding.colors.count, 3)
        let threeColorBranding = branding

        binding.editorRemoveColor(for: .primary)
        XCTAssertEqual(branding, threeColorBranding)

        binding.editorRemoveColor(for: .secondary)
        XCTAssertEqual(branding.colors, [.ink, .ocean])
    }

    // MARK: - Rendering version

    func testClassicVocabularyStillEncodesTheShippedRenderingVersion() throws {
        let classic = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(symbol: .mountain)
        )

        XCTAssertEqual(
            classic.renderingVersion,
            BrowserSpaceBranding.baselineRenderingVersion
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(classic))
                as? [String: Any]
        )
        XCTAssertEqual(
            object["renderingVersion"] as? Int,
            BrowserSpaceBranding.baselineRenderingVersion
        )
    }

    func testExpandedChargesAnnounceTheNewRenderingVersion() throws {
        var expanded = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(symbol: .crown)
        )

        XCTAssertEqual(
            expanded.renderingVersion,
            BrowserSpaceBranding.currentRenderingVersion
        )
        XCTAssertEqual(BrowserSpaceBranding.currentRenderingVersion, 3)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(expanded))
                as? [String: Any]
        )
        XCTAssertEqual(object["renderingVersion"] as? Int, 3)

        expanded.crest.symbol = .mountain

        XCTAssertEqual(
            expanded.renderingVersion,
            BrowserSpaceBranding.baselineRenderingVersion
        )
    }

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
        crest["fieldDivision"] = "perSaltire"
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
        crest["symbol"] = "wyvern"
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

    func testCuratedPaletteSwatchesNameEveryTinctureTheyShow() {
        // The swatch reads its colors out for VoiceOver, so no palette may fall
        // back to the unnamed "Custom" label.
        for preset in BrowserSpaceBrandingPreset.curated {
            for color in preset.colors {
                XCTAssertNotEqual(
                    color.title,
                    "Custom",
                    "\(preset.title) has an unnamed tincture."
                )
            }
        }
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

    func testApplyingACuratedPalettePreservesTheChosenSurfaceAndCrest() throws {
        var source = BrowserSpaceBranding(
            colors: [.rose],
            bannerPattern: .chevron,
            bannerStrength: 0.72,
            readabilityFade: 0.38,
            themeMode: .gradient,
            gradientAngle: 147,
            showsTexture: true,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .seal,
                fieldDivision: .perBend,
                ordinary: .bordure,
                trim: .laurel,
                symbol: .bird,
                chargeLayout: .paired
            )
        )
        let originalCrest = source.crest

        source = try XCTUnwrap(BrowserSpaceBrandingPreset.curated.first).applying(to: source)

        XCTAssertEqual(source.colors, BrowserSpaceHousePalette.winter.colors)
        XCTAssertEqual(source.themeMode, .gradient)
        XCTAssertEqual(source.gradientAngle, 147)
        XCTAssertTrue(source.showsTexture)
        XCTAssertEqual(source.bannerPattern, .chevron)
        XCTAssertEqual(source.bannerStrength, 0.72)
        XCTAssertEqual(source.readabilityFade, 0.38)
        XCTAssertEqual(source.iconStyle, .layeredCrest)
        XCTAssertEqual(source.crest, originalCrest.normalized(forColorCount: 3))
    }

    func testAutomaticallyCreatedSpacesStartWithAHigherReadabilityFade() throws {
        var session = BrowserSession.preview

        XCTAssertTrue(
            session.spaces.allSatisfy {
                $0.branding.readabilityFade == BrowserSpaceBranding.initialReadabilityFade
            })

        session.addSpace()

        XCTAssertEqual(
            try XCTUnwrap(session.selectedSpace).branding.readabilityFade,
            BrowserSpaceBranding.initialReadabilityFade
        )
        XCTAssertEqual(BrowserSpaceBranding.initialReadabilityFade, 0.45)
    }

    func testSpaceIdentityArtworkUsesTheLayeredCrestWhenSelected() throws {
        var space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        space.branding.iconStyle = .layeredCrest

        XCTAssertEqual(BrowserSpaceIdentityArtwork(space: space), .crest)

        space.branding.iconStyle = .simpleSymbol

        XCTAssertEqual(BrowserSpaceIdentityArtwork(space: space), .symbol(space.symbol))
    }

    func testSpaceSymbolArtworkRendersLayeredCrestAsOnePlatformImage() throws {
        var space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        space.branding.iconStyle = .layeredCrest
        space.branding.crest.chargeLayout = .trio
        space.branding.crest.trim = .laurel
        let renderer = ImageRenderer(
            content: BrowserSpaceSymbolArtwork(
                space: space,
                size: 30,
                lockSize: 7
            )
        )

        XCTAssertNotNil(renderer.nsImage)
    }

    func testBrandingNormalizesPaletteAndLayerColorSelections() {
        let customBlue = BrowserSpaceBrandColor(
            red: 0.12,
            green: 0.42,
            blue: 0.88
        )
        let branding = BrowserSpaceBranding(
            colors: [.ink, customBlue, .gold, .rose, customBlue],
            bannerPattern: .diagonal,
            bannerStrength: 2,
            readabilityFade: 2,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .shield,
                fieldDivision: .quarterly,
                ordinary: .bend,
                trim: .laurel,
                symbol: .mountain,
                chargeLayout: .trio,
                backplateColorIndex: 9,
                secondaryFieldColorIndex: 8,
                ordinaryColorIndex: -3,
                trimColorIndex: -1,
                symbolColorIndex: 7
            )
        )

        XCTAssertEqual(branding.colors, [.ink, customBlue, .gold])
        XCTAssertEqual(branding.bannerStrength, 1)
        XCTAssertEqual(branding.readabilityFade, 1)
        XCTAssertEqual(branding.crest.backplateColorIndex, 0)
        XCTAssertEqual(branding.crest.secondaryFieldColorIndex, 0)
        XCTAssertEqual(branding.crest.ordinaryColorIndex, 0)
        XCTAssertEqual(branding.crest.trimColorIndex, 0)
        XCTAssertEqual(branding.crest.symbolColorIndex, 0)
    }

    func testBrandingPreservesDuplicateColorsInTheirNamedSlots() {
        let branding = BrowserSpaceBranding(
            colors: [.ink, .ink, .gold]
        )

        XCTAssertEqual(branding.colors, [.ink, .ink, .gold])
    }

    func testGradientThemeSettingsNormalizeAndRoundTrip() throws {
        let source = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
                as? [String: Any]
        )
        object["themeMode"] = "gradient"
        object["gradientAngle"] = 405
        object["showsTexture"] = true

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
                as? [String: Any]
        )

        XCTAssertEqual(decoded.themeMode, .gradient)
        XCTAssertEqual(decoded.gradientAngle, 45)
        XCTAssertTrue(decoded.showsTexture)
        XCTAssertEqual(encodedObject["themeMode"] as? String, "gradient")
        XCTAssertEqual(encodedObject["gradientAngle"] as? Double, 45)
        XCTAssertEqual(encodedObject["showsTexture"] as? Bool, true)
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

    func testRoleColorsUseTheNearestConfiguredSlotAsFallback() {
        let oneColor = BrowserSpaceBranding(colors: [.ink])
        let twoColors = BrowserSpaceBranding(colors: [.ink, .ocean])

        XCTAssertEqual(oneColor.backgroundColor, .ink)
        XCTAssertEqual(oneColor.primaryColor, .ink)
        XCTAssertEqual(oneColor.secondaryColor, .ink)
        XCTAssertEqual(twoColors.backgroundColor, .ink)
        XCTAssertEqual(twoColors.primaryColor, .ocean)
        XCTAssertEqual(twoColors.secondaryColor, .ocean)
    }

    func testGradientThemeRendersAsAPlatformImage() {
        let branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerStrength: 0.35,
            readabilityFade: 0.2,
            themeMode: .gradient,
            gradientAngle: 127,
            showsTexture: true
        )
        let renderer = ImageRenderer(
            content: BrowserSpaceBannerBackground(branding: branding)
                .frame(width: 420, height: 240)
        )

        XCTAssertNotNil(renderer.nsImage)
    }

    func testGradientTextureProducesAPerceptibleRenderedDifference() throws {
        let plain = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerStrength: 1,
            readabilityFade: 0.2,
            themeMode: .gradient,
            gradientAngle: 127,
            showsTexture: false
        )
        var textured = plain
        textured.showsTexture = true

        let plainPixels = try renderedPixels(for: plain)
        let texturedPixels = try renderedPixels(for: textured)
        XCTAssertEqual(plainPixels.count, texturedPixels.count)

        var changedPixelCount = 0
        var totalChannelDifference = 0
        for pixelOffset in stride(from: 0, to: plainPixels.count, by: 4) {
            let channelDifferences = (0..<3).map { channel in
                abs(
                    Int(plainPixels[pixelOffset + channel])
                        - Int(texturedPixels[pixelOffset + channel])
                )
            }
            if channelDifferences.max() ?? 0 >= 2 {
                changedPixelCount += 1
            }
            totalChannelDifference += channelDifferences.reduce(0, +)
        }

        let pixelCount = plainPixels.count / 4
        let changedPixelRatio = Double(changedPixelCount) / Double(pixelCount)
        let meanChannelDifference = Double(totalChannelDifference) / Double(pixelCount * 3)
        XCTAssertGreaterThan(changedPixelRatio, 0.02)
        XCTAssertGreaterThan(meanChannelDifference, 0.5)
    }

    func testLegacyNamedColorAndCustomColorBothRoundTrip() throws {
        let legacyData = try XCTUnwrap("\"ocean\"".data(using: .utf8))
        let legacy = try JSONDecoder().decode(BrowserSpaceBrandColor.self, from: legacyData)
        XCTAssertEqual(legacy, .ocean)

        let custom = BrowserSpaceBrandColor(
            red: 0.17,
            green: 0.53,
            blue: 0.91,
            alpha: 0.84
        )
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrandColor.self,
            from: JSONEncoder().encode(custom)
        )
        XCTAssertEqual(decoded, custom)
    }

    private func renderedPixels(for branding: BrowserSpaceBranding) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: BrowserSpaceBannerBackground(branding: branding)
                .frame(width: 320, height: 180)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
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
