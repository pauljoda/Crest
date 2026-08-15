import AppKit
import SwiftUI
import XCTest
@testable import Crest

final class CrestDesignLanguageTests: XCTestCase {
    func testDesignTokensExposeOneSharedVisualScale() {
        XCTAssertEqual(CrestSpacing.extraExtraSmall, 2)
        XCTAssertEqual(CrestSpacing.extraSmall, 4)
        XCTAssertEqual(CrestSpacing.small, 8)
        XCTAssertEqual(CrestSpacing.medium, 12)
        XCTAssertEqual(CrestSpacing.large, 16)
        XCTAssertEqual(CrestSpacing.extraLarge, 20)
        XCTAssertEqual(CrestSpacing.extraExtraLarge, 24)
        XCTAssertEqual(CrestSpacing.section, 32)
        XCTAssertEqual(CrestSpacing.screen, 40)

        XCTAssertEqual(CrestRadius.compact, 8)
        XCTAssertEqual(CrestRadius.control, 12)
        XCTAssertEqual(CrestRadius.card, 16)
        XCTAssertEqual(CrestRadius.panel, 24)

        XCTAssertEqual(CrestOpacity.hover, 0.08)
        XCTAssertEqual(CrestOpacity.chromeSurface, 0.055)
        XCTAssertEqual(CrestOpacity.interactionSelection, 0.13)
        XCTAssertEqual(CrestOpacity.interactionSelectionBorder, 0.10)
        XCTAssertEqual(CrestOpacity.interactionSelectionShadow, 0.08)
        XCTAssertEqual(CrestOpacity.selection, CrestOpacity.interactionSelection)
        XCTAssertEqual(CrestOpacity.pinnedSelection, CrestOpacity.interactionSelection)
        XCTAssertEqual(
            CrestOpacity.pinnedSelectionBorder,
            CrestOpacity.interactionSelectionBorder
        )
        XCTAssertEqual(
            CrestOpacity.pinnedSelectionShadow,
            CrestOpacity.interactionSelectionShadow
        )
        XCTAssertEqual(CrestOpacity.disabled, 0.5)
        XCTAssertEqual(CrestOpacity.controlDisabledForeground, 0.48)
        XCTAssertEqual(CrestLayout.hairline, 1)
        XCTAssertEqual(CrestLayout.sidebarRowHeight, 40)
        XCTAssertEqual(CrestLayout.sidebarControlCornerRadius, CrestRadius.compact)
        XCTAssertEqual(CrestLayout.pinnedAccentBorderWidth, 2)
        XCTAssertEqual(CrestLayout.reloadQuarterTurn, 90)
        XCTAssertEqual(
            CrestColor.dropIndicator,
            CrestBrandPalette.paper.opacity(0.72)
        )
    }

    func testPlatformHitTargetUsesNativeMinimums() {
        #if os(macOS)
        XCTAssertEqual(CrestLayout.minimumHitTarget, 28)
        #else
        XCTAssertEqual(CrestLayout.minimumHitTarget, 44)
        #endif
    }

    func testOnboardingUsesTheWebsiteBrandPalette() {
        XCTAssertEqual(CrestBrandPalette.inkComponents, .init(red: 23, green: 34, blue: 56))
        XCTAssertEqual(CrestBrandPalette.inkSoftComponents, .init(red: 39, green: 54, blue: 83))
        XCTAssertEqual(CrestBrandPalette.paperComponents, .init(red: 255, green: 250, blue: 240))
        XCTAssertEqual(CrestBrandPalette.parchmentComponents, .init(red: 243, green: 234, blue: 214))
        XCTAssertEqual(CrestBrandPalette.butterComponents, .init(red: 231, green: 189, blue: 88))
        XCTAssertEqual(CrestBrandPalette.coralComponents, .init(red: 237, green: 90, blue: 67))
        XCTAssertEqual(CrestBrandPalette.sageComponents, .init(red: 129, green: 155, blue: 121))
        XCTAssertEqual(CrestBrandPalette.skyComponents, .init(red: 98, green: 169, blue: 216))

        XCTAssertEqual(BrowserOnboardingPalette.inkComponents, .init(red: 23, green: 34, blue: 56))
        XCTAssertEqual(BrowserOnboardingPalette.inkSoftComponents, .init(red: 39, green: 54, blue: 83))
        XCTAssertEqual(BrowserOnboardingPalette.paperComponents, .init(red: 255, green: 250, blue: 240))
        XCTAssertEqual(BrowserOnboardingPalette.parchmentComponents, .init(red: 243, green: 234, blue: 214))
        XCTAssertEqual(BrowserOnboardingPalette.butterComponents, .init(red: 231, green: 189, blue: 88))
        XCTAssertEqual(BrowserOnboardingPalette.coralComponents, .init(red: 237, green: 90, blue: 67))
        XCTAssertEqual(BrowserOnboardingPalette.sageComponents, .init(red: 129, green: 155, blue: 121))
        XCTAssertEqual(BrowserOnboardingPalette.skyComponents, .init(red: 98, green: 169, blue: 216))
    }

    func testSpaceAtmosphereStaysWithinTheDocumentedLightAndDarkRanges() {
        let accent = SpaceAccent.indigo

        XCTAssertEqual(
            accent.primaryAtmosphereOpacity(colorScheme: .light, contrast: .standard),
            0.12,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            accent.primaryAtmosphereOpacity(colorScheme: .dark, contrast: .standard),
            0.20,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            accent.primaryAtmosphereOpacity(colorScheme: .light, contrast: .increased),
            0.14,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            accent.primaryAtmosphereOpacity(colorScheme: .dark, contrast: .increased),
            0.22,
            accuracy: 0.0001
        )
    }

    func testSecondaryAtmosphereRemainsSubordinateToTheSpaceWash() {
        for colorScheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                XCTAssertLessThan(
                    SpaceAccent.indigo.secondaryAtmosphereOpacity(
                        colorScheme: colorScheme,
                        contrast: contrast
                    ),
                    SpaceAccent.indigo.primaryAtmosphereOpacity(
                        colorScheme: colorScheme,
                        contrast: contrast
                    )
                )
            }
        }
    }

    func testDisplayAndSansRolesNameTheBrandFaces() {
        XCTAssertEqual(CrestTypography.displayFontName, "Iowan Old Style")
        XCTAssertEqual(CrestTypography.sansFontName, "Avenir Next")

        XCTAssertEqual(
            NSFont(name: CrestTypography.displayFontName, size: 12)?.fontName,
            "IowanOldStyle-Roman",
            "The display face must ship with the OS so nothing is embedded."
        )
        XCTAssertEqual(
            NSFont(name: CrestTypography.sansFontName, size: 12)?.fontName,
            "AvenirNext-Regular",
            "The sans face must ship with the OS so nothing is embedded."
        )

        XCTAssertEqual(
            CrestTypography.display(46, relativeTo: .largeTitle),
            Font.custom("Iowan Old Style", size: 46, relativeTo: .largeTitle)
        )
        XCTAssertEqual(
            CrestTypography.display(46),
            Font.custom("Iowan Old Style", size: 46)
        )
        XCTAssertEqual(
            CrestTypography.sans(14, weight: .bold),
            Font.custom("Avenir Next", size: 14).weight(.bold)
        )
        XCTAssertEqual(
            CrestTypography.sans(14),
            Font.custom("Avenir Next", size: 14).weight(.regular)
        )
    }

    func testNamedDisplayRolesScaleAgainstTheMatchingTextStyles() {
        XCTAssertEqual(CrestTypography.displayHeroSize, 46)
        XCTAssertEqual(CrestTypography.displayPageSize, 24)
        XCTAssertEqual(CrestTypography.displaySectionSize, 17)

        XCTAssertEqual(
            CrestTypography.displayHero,
            CrestTypography.display(CrestTypography.displayHeroSize, relativeTo: .largeTitle)
        )
        XCTAssertEqual(
            CrestTypography.displayPage,
            CrestTypography.display(CrestTypography.displayPageSize, relativeTo: .title2)
        )
        XCTAssertEqual(
            CrestTypography.displaySection,
            CrestTypography.display(CrestTypography.displaySectionSize, relativeTo: .title3)
        )
    }

    func testOnboardingTypographyForwardsToTheSharedScale() {
        XCTAssertEqual(
            BrowserOnboardingTypography.display(46),
            CrestTypography.display(46)
        )
        XCTAssertEqual(
            BrowserOnboardingTypography.display(42),
            CrestTypography.display(42)
        )
        XCTAssertEqual(
            BrowserOnboardingTypography.sans(13, weight: .semibold),
            CrestTypography.sans(13, weight: .semibold)
        )
        XCTAssertEqual(
            BrowserOnboardingTypography.sans(11),
            CrestTypography.sans(11)
        )
    }

    func testMotionDurationsPinOneSharedPacing() {
        XCTAssertEqual(CrestMotion.paneTransition, 0.22, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.stepTransition, 0.30, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.pressFeedback, 0.14, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.compactPressFeedback, 0.12, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.developerPressFeedback, 0.16, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.surfaceTransition, 0.12, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.collectionTransition, 0.22, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.dragPreviewTransition, 0.18, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.navigationTransition, 0.28, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.chromeTransition, 0.28, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.floatingPaneTransition, 0.24, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.toolbarTransition, 0.24, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.dismissalTransition, 0.18, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.windowBackdropTransition, 0.16, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.hoverTransition, 0.14, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.disclosureTransition, 0.20, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.loadingProgressTransition, 0.22, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.selectionTransition, 0.20, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.dragSourceTransition, 0.20, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.scrollAlignmentTransition, 0.24, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.contentNavigationTransition, 0.42, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.spaceSwipeTransition, 0.32, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.peekEntranceTransition, 0.28, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.quickPeekEntranceTransition, 0.34, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.contentRevealTransition, 0.12, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.paletteTransition, 0.18, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.recoveryTransition, 0.18, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.contentStateTransition, 0.22, accuracy: 0.0001)
        XCTAssertEqual(
            CrestMotion.feedbackPresentationTransition,
            0.22,
            accuracy: 0.0001
        )
        XCTAssertEqual(CrestMotion.peekDragSettlementTransition, 0.30, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.peekDismissalTransition, 0.22, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.utilityFanRevealTransition, 0.42, accuracy: 0.0001)
        XCTAssertEqual(CrestMotion.utilityFanDismissTransition, 0.26, accuracy: 0.0001)
        XCTAssertEqual(
            CrestMotion.utilityFanDismissCompletionDelay,
            .milliseconds(260)
        )
        XCTAssertEqual(CrestMotion.reloadFeedbackDuration, .milliseconds(240))
        XCTAssertEqual(CrestMotion.reloadFeedbackPhaseDuration, .milliseconds(120))
        XCTAssertEqual(CrestMotion.reloadFeedbackPhaseSeconds, 0.12, accuracy: 0.0001)

        XCTAssertEqual(CrestMotion.pane, .snappy(duration: CrestMotion.paneTransition))
        XCTAssertEqual(CrestMotion.step, .snappy(duration: CrestMotion.stepTransition))
        XCTAssertEqual(CrestMotion.onboardingStep, .default)
        XCTAssertEqual(CrestMotion.onboardingProgress, .snappy)
        XCTAssertEqual(CrestMotion.onboardingPresentation, .snappy)
        XCTAssertEqual(CrestMotion.press, .easeOut(duration: CrestMotion.pressFeedback))
        XCTAssertEqual(
            CrestMotion.compactPress,
            .easeOut(duration: CrestMotion.compactPressFeedback)
        )
        XCTAssertEqual(
            CrestMotion.developerPress,
            .snappy(duration: CrestMotion.developerPressFeedback)
        )
        XCTAssertEqual(
            CrestMotion.surface,
            .easeInOut(duration: CrestMotion.surfaceTransition)
        )
        XCTAssertEqual(
            CrestMotion.collection,
            .snappy(duration: CrestMotion.collectionTransition)
        )
        XCTAssertEqual(
            CrestMotion.dragPreview,
            .smooth(duration: CrestMotion.dragPreviewTransition)
        )
        XCTAssertEqual(
            CrestMotion.navigation,
            .snappy(duration: CrestMotion.navigationTransition)
        )
        XCTAssertEqual(
            CrestMotion.chrome,
            .smooth(duration: CrestMotion.chromeTransition)
        )
        XCTAssertEqual(
            CrestMotion.floatingPane,
            .smooth(duration: CrestMotion.floatingPaneTransition)
        )
        XCTAssertEqual(
            CrestMotion.toolbar,
            .snappy(duration: CrestMotion.toolbarTransition)
        )
        XCTAssertEqual(
            CrestMotion.dismissal,
            .easeOut(duration: CrestMotion.dismissalTransition)
        )
        XCTAssertEqual(
            CrestMotion.windowBackdrop,
            .easeInOut(duration: CrestMotion.windowBackdropTransition)
        )
        XCTAssertEqual(
            CrestMotion.hover,
            .easeInOut(duration: CrestMotion.hoverTransition)
        )
        XCTAssertEqual(
            CrestMotion.disclosure,
            .snappy(duration: CrestMotion.disclosureTransition)
        )
        XCTAssertEqual(
            CrestMotion.loadingProgress,
            .smooth(duration: CrestMotion.loadingProgressTransition)
        )
        XCTAssertEqual(
            CrestMotion.selection,
            .easeInOut(duration: CrestMotion.selectionTransition)
        )
        XCTAssertEqual(
            CrestMotion.dragSource,
            .snappy(duration: CrestMotion.dragSourceTransition)
        )
        XCTAssertEqual(
            CrestMotion.scrollAlignment,
            .snappy(duration: CrestMotion.scrollAlignmentTransition, extraBounce: 0)
        )
        XCTAssertEqual(
            CrestMotion.spaceSwipe,
            .snappy(duration: CrestMotion.spaceSwipeTransition, extraBounce: 0)
        )
        XCTAssertEqual(
            CrestMotion.peekEntrance,
            .spring(duration: CrestMotion.peekEntranceTransition, bounce: 0.2)
        )
        XCTAssertEqual(
            CrestMotion.quickPeekEntrance,
            .smooth(duration: CrestMotion.quickPeekEntranceTransition)
        )
        XCTAssertEqual(
            CrestMotion.contentReveal,
            .easeOut(duration: CrestMotion.contentRevealTransition)
        )
        XCTAssertEqual(
            CrestMotion.palette,
            .easeInOut(duration: CrestMotion.paletteTransition)
        )
        XCTAssertEqual(
            CrestMotion.recovery,
            .easeInOut(duration: CrestMotion.recoveryTransition)
        )
        XCTAssertEqual(
            CrestMotion.contentState,
            .snappy(duration: CrestMotion.contentStateTransition)
        )
        XCTAssertEqual(
            CrestMotion.feedbackPresentation,
            .snappy(duration: CrestMotion.feedbackPresentationTransition)
        )
        XCTAssertEqual(
            CrestMotion.peekDragSettlement,
            .snappy(duration: CrestMotion.peekDragSettlementTransition)
        )
        XCTAssertEqual(
            CrestMotion.peekDismissal,
            .snappy(duration: CrestMotion.peekDismissalTransition)
        )
        XCTAssertEqual(
            CrestMotion.contentNavigation,
            .snappy(duration: CrestMotion.contentNavigationTransition, extraBounce: 0.04)
        )
        XCTAssertEqual(
            CrestMotion.utilityFanReveal,
            .smooth(duration: CrestMotion.utilityFanRevealTransition, extraBounce: 0.05)
        )
        XCTAssertEqual(
            CrestMotion.utilityFanDismiss,
            .smooth(duration: CrestMotion.utilityFanDismissTransition, extraBounce: 0)
        )
        XCTAssertEqual(
            CrestMotion.reloadTurnOut,
            .easeOut(duration: CrestMotion.reloadFeedbackPhaseSeconds)
        )
        XCTAssertEqual(
            CrestMotion.reloadTurnIn,
            .easeIn(duration: CrestMotion.reloadFeedbackPhaseSeconds)
        )
    }

    func testBrandThemePinsItsLightAndDarkComponents() {
        XCTAssertEqual(
            CrestBrandTheme.accentLightComponents,
            .init(red: 237, green: 90, blue: 67)
        )
        XCTAssertEqual(
            CrestBrandTheme.accentDarkComponents,
            .init(red: 241, green: 117, blue: 98)
        )
        XCTAssertEqual(
            CrestBrandTheme.canvasLightComponents,
            .init(red: 255, green: 250, blue: 240)
        )
        XCTAssertEqual(
            CrestBrandTheme.canvasDarkComponents,
            .init(red: 23, green: 34, blue: 56)
        )
        XCTAssertEqual(
            CrestBrandTheme.surfaceLightComponents,
            .init(red: 243, green: 234, blue: 214)
        )
        XCTAssertEqual(
            CrestBrandTheme.surfaceDarkComponents,
            .init(red: 39, green: 54, blue: 83)
        )
        XCTAssertEqual(
            CrestBrandTheme.textDisplayLightComponents,
            .init(red: 23, green: 34, blue: 56)
        )
        XCTAssertEqual(
            CrestBrandTheme.textDisplayDarkComponents,
            .init(red: 255, green: 250, blue: 240)
        )
        XCTAssertEqual(
            CrestBrandTheme.lineLightComponents,
            .init(red: 23, green: 34, blue: 56)
        )
        XCTAssertEqual(
            CrestBrandTheme.lineDarkComponents,
            .init(red: 255, green: 250, blue: 240)
        )
        XCTAssertEqual(CrestBrandTheme.lineLightOpacity, 0.18, accuracy: 0.0001)
        XCTAssertEqual(CrestBrandTheme.lineDarkOpacity, 0.22, accuracy: 0.0001)
    }

    func testBrandThemeDynamicRolesFollowTheColorScheme() {
        for colorScheme in [ColorScheme.light, .dark] {
            assertSameResolvedColor(
                CrestBrandTheme.accent,
                CrestBrandTheme.accent(colorScheme),
                colorScheme: colorScheme
            )
            assertSameResolvedColor(
                CrestBrandTheme.canvas,
                CrestBrandTheme.canvas(colorScheme),
                colorScheme: colorScheme
            )
            assertSameResolvedColor(
                CrestBrandTheme.surface,
                CrestBrandTheme.surface(colorScheme),
                colorScheme: colorScheme
            )
            assertSameResolvedColor(
                CrestBrandTheme.textDisplay,
                CrestBrandTheme.textDisplay(colorScheme),
                colorScheme: colorScheme
            )
        }
    }

    func testBrandThemeClearsContrastMinimumsInBothSchemes() {
        for colorScheme in [ColorScheme.light, .dark] {
            let textOnCanvas = BrowserVisualAccessibilityPolicy.contrastRatio(
                foreground: CrestBrandTheme.textDisplay(colorScheme),
                background: CrestBrandTheme.canvas(colorScheme),
                colorScheme: colorScheme
            )
            XCTAssertGreaterThanOrEqual(
                textOnCanvas,
                4.5,
                "Display text on canvas must clear WCAG AA in \(colorScheme)."
            )

            let textOnSurface = BrowserVisualAccessibilityPolicy.contrastRatio(
                foreground: CrestBrandTheme.textDisplay(colorScheme),
                background: CrestBrandTheme.surface(colorScheme),
                colorScheme: colorScheme
            )
            XCTAssertGreaterThanOrEqual(
                textOnSurface,
                4.5,
                "Display text on surface must clear WCAG AA in \(colorScheme)."
            )

            let accentOnCanvas = BrowserVisualAccessibilityPolicy.contrastRatio(
                foreground: CrestBrandTheme.accent(colorScheme),
                background: CrestBrandTheme.canvas(colorScheme),
                colorScheme: colorScheme
            )
            XCTAssertGreaterThanOrEqual(
                accentOnCanvas,
                3.0,
                "Accent on canvas must clear the non-text minimum in \(colorScheme)."
            )
        }
    }

    // MARK: - CrestControls component library

    func testButtonMetricsPinOnePressAndOneDisabledState() {
        XCTAssertEqual(CrestButtonMetrics.pressedScale, 0.975)
        XCTAssertEqual(CrestButtonMetrics.disabledOpacity, 0.42)
        XCTAssertEqual(CrestButtonMetrics.prominentHeight, 40)
        XCTAssertEqual(CrestButtonMetrics.standardHeight, 38)
        XCTAssertEqual(
            CrestButtonMetrics.prominentHorizontalPadding,
            CrestSpacing.extraLarge
        )
        XCTAssertEqual(
            CrestButtonMetrics.standardHorizontalPadding,
            CrestSpacing.large
        )
        XCTAssertEqual(CrestButtonMetrics.quietHorizontalPadding, CrestSpacing.small)
        XCTAssertEqual(CrestButtonMetrics.strokeWidth, CrestLayout.hairline)
        XCTAssertEqual(CrestButtonMetrics.prominentLabelSize, 14)
        XCTAssertEqual(CrestButtonMetrics.standardLabelSize, 13)

        // The butter capsule's ink hairline is the same decision as every other
        // Crest hairline, not a second opinion about it.
        XCTAssertEqual(
            CrestButtonMetrics.inkStrokeOpacity,
            CrestBrandTheme.lineLightOpacity
        )
        XCTAssertEqual(CrestButtonMetrics.inkStrokeOpacity, 0.18)
    }

    func testIconButtonReachesThePlatformHitTarget() {
        XCTAssertEqual(CrestButtonMetrics.iconDiameter, 34)
        XCTAssertGreaterThanOrEqual(
            CrestButtonMetrics.iconHitTarget,
            CrestLayout.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            CrestButtonMetrics.iconHitTarget,
            CrestButtonMetrics.iconDiameter
        )
    }

    func testTintedWashRampOnlyEverDeepens() {
        XCTAssertLessThan(
            CrestButtonMetrics.tintRestFill,
            CrestButtonMetrics.tintEmphasizedFill
        )
        XCTAssertLessThan(
            CrestButtonMetrics.tintEmphasizedFill,
            CrestButtonMetrics.tintPressedFill
        )
        XCTAssertLessThan(
            CrestButtonMetrics.tintRestStroke,
            CrestButtonMetrics.tintEmphasizedStroke
        )
        XCTAssertLessThan(
            CrestButtonMetrics.quietStrokeWidth,
            CrestButtonMetrics.prominentStrokeWidth
        )
    }

    func testButtonRoleFactoriesNameTheRoleAndLeaveTheTintToTheBrand() {
        XCTAssertEqual(CrestButtonStyle.crestPrimary.role, .primary)
        XCTAssertNil(CrestButtonStyle.crestPrimary.tint)
        XCTAssertEqual(CrestButtonStyle.crestSecondary.role, .secondary)
        XCTAssertEqual(CrestButtonStyle.crestTertiary.role, .tertiary)
        XCTAssertEqual(CrestButtonStyle.crestDestructive.role, .destructive)
        XCTAssertEqual(
            CrestButtonStyle.crestIcon().role,
            .icon(diameter: CrestButtonMetrics.iconDiameter, isProminent: false)
        )
        XCTAssertEqual(
            CrestButtonStyle.crestIcon(isProminent: true).role,
            .icon(diameter: CrestButtonMetrics.iconDiameter, isProminent: true)
        )
        XCTAssertEqual(
            CrestButtonStyle.crestPrimary(tint: CrestBrandPalette.sage).tint,
            CrestBrandPalette.sage
        )
    }

    func testEveryCrestControlAnswersAPressWithTheSharedMotionRole() {
        // Components never spell a duration; they take the control role and let
        // Reduce Motion drop it entirely.
        XCTAssertEqual(CrestMotion.press, .easeOut(duration: CrestMotion.pressFeedback))
        XCTAssertEqual(CrestMotion.pressFeedback, 0.14)
        XCTAssertNil(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.press,
                reduceMotion: true
            )
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialScale(
                CrestButtonMetrics.pressedScale,
                reduceMotion: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialScale(
                CrestButtonMetrics.pressedScale,
                reduceMotion: false
            ),
            CrestButtonMetrics.pressedScale
        )
        XCTAssertEqual(CrestMotion.surfaceTransition, 0.12)
        XCTAssertEqual(
            CrestMotion.surface,
            .easeInOut(duration: CrestMotion.surfaceTransition)
        )
    }

    func testFieldTreatmentUsesTheControlRadiusAndTheFocusRingToken() {
        XCTAssertEqual(CrestFieldMetrics.cornerRadius, CrestRadius.control)
        XCTAssertEqual(CrestFieldMetrics.height, 40)
        XCTAssertEqual(CrestFieldMetrics.horizontalPadding, CrestSpacing.medium)
        XCTAssertEqual(CrestFieldMetrics.borderWidth, CrestLayout.hairline)
        XCTAssertEqual(CrestFieldMetrics.focusRingWidth, CrestLayout.focusRing)
        XCTAssertEqual(CrestFieldMetrics.focusRingWidth, 3)
    }

    func testSelectableCardBorrowsTheSidebarSelectionWeight() {
        XCTAssertEqual(CrestSelectableCardMetrics.selectedBorderWidth, 2)
        XCTAssertEqual(
            CrestSelectableCardMetrics.selectedBorderWidth,
            CrestLayout.pinnedAccentBorderWidth
        )
        XCTAssertEqual(
            CrestSelectableCardMetrics.restingBorderWidth,
            CrestLayout.hairline
        )
        XCTAssertLessThan(
            CrestSelectableCardMetrics.restingBorderWidth,
            CrestSelectableCardMetrics.selectedBorderWidth
        )
        XCTAssertEqual(CrestSelectableCardMetrics.cornerRadius, CrestRadius.card)
        XCTAssertEqual(CrestSelectableCardMetrics.padding, CrestSpacing.large)
        XCTAssertEqual(
            CrestSelectableCardMetrics.contentSpacing,
            CrestSpacing.medium
        )
        XCTAssertEqual(
            CrestSelectableCardMetrics.checkmarkSymbol,
            "checkmark.circle.fill"
        )
    }

    func testSpaceChipReusesTheButtonStrokeWeightsAndStaysTouchable() {
        XCTAssertEqual(CrestSpaceIconPickerMetrics.selectionFillOpacity, 0.2)
        XCTAssertEqual(
            CrestSpaceIconPickerMetrics.trackBorderOpacity,
            CrestOpacity.border
        )
        XCTAssertEqual(CrestSpaceChipMetrics.baseHeight, 42)
        XCTAssertGreaterThanOrEqual(
            CrestSpaceChipMetrics.height,
            CrestLayout.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            CrestSpaceChipMetrics.height,
            CrestSpaceChipMetrics.baseHeight
        )
        XCTAssertEqual(CrestSpaceChipMetrics.cornerRadius, CrestRadius.control)
        XCTAssertEqual(
            CrestSpaceChipMetrics.selectedStrokeWidth,
            CrestButtonMetrics.prominentStrokeWidth
        )
        XCTAssertEqual(
            CrestSpaceChipMetrics.restingStrokeWidth,
            CrestButtonMetrics.quietStrokeWidth
        )
        XCTAssertEqual(CrestSpaceChipMetrics.iconSize, 24)
        XCTAssertEqual(CrestSpaceChipMetrics.lockSize, 24 * 0.24, accuracy: 0.001)
        XCTAssertEqual(CrestSpaceChipMetrics.dashPattern, [6, 5])
    }

    func testSpaceIdentityPrefersTheDisplayNameAndAnOverriddenTint() {
        guard let space = BrowserSession.preview.spaces.first else {
            return XCTFail("The preview session must ship at least one Space.")
        }

        let plain = CrestSpaceIdentity(space: space)
        XCTAssertEqual(plain.id, space.id)
        XCTAssertEqual(plain.name, space.name)
        XCTAssertEqual(plain.tint, space.accent.color)

        let draft = CrestSpaceIdentity(
            space: space,
            displayName: "Untitled Space",
            tint: CrestBrandPalette.sage
        )
        XCTAssertEqual(draft.id, space.id)
        XCTAssertEqual(draft.name, "Untitled Space")
        XCTAssertEqual(draft.tint, CrestBrandPalette.sage)

        XCTAssertEqual(
            CrestSpaceIdentity.list(BrowserSession.preview.spaces).map(\.id),
            BrowserSession.preview.spaces.map(\.id)
        )
    }

    func testSpaceChipCommandsAreDistinctAndOnlyDeleteIsDestructive() {
        var renamed = false
        let rename = CrestSpaceChipCommand.rename { renamed = true }
        rename.perform()
        XCTAssertTrue(renamed)
        XCTAssertEqual(rename.id, "rename")
        XCTAssertFalse(rename.isDestructive)

        let customize = CrestSpaceChipCommand.customize {}
        XCTAssertEqual(customize.id, "customize")
        XCTAssertFalse(customize.isDestructive)

        let delete = CrestSpaceChipCommand.delete {}
        XCTAssertEqual(delete.id, "delete")
        XCTAssertTrue(delete.isDestructive)

        XCTAssertEqual(Set([rename.id, customize.id, delete.id]).count, 3)
    }

    func testFormRowsStayReachableAndShareTheIconTile() {
        XCTAssertEqual(
            CrestFormRowMetrics.minimumHeight,
            CrestLayout.minimumHitTarget
        )
        XCTAssertEqual(CrestFormRowMetrics.iconTileSize, 30)
        XCTAssertEqual(CrestFormRowMetrics.iconSymbolSize, 14)
        XCTAssertEqual(CrestFormRowMetrics.contentSpacing, CrestSpacing.medium)
    }

    func testSettingsPresentationUsesNamedComponentMetrics() {
        XCTAssertEqual(
            CrestSettingsPresentationMetrics.statusSpacing,
            CrestSpacing.large
        )
        XCTAssertEqual(
            CrestSettingsPresentationMetrics.titleSpacing,
            CrestFormRowMetrics.titleSpacing
        )
        XCTAssertEqual(
            CrestSettingsPresentationMetrics.regularIconSize,
            CrestSpacing.section
        )
    }

    func testTextWeightAccentClearsTextContrastWhereTheTintOnlyClearsThree() {
        for colorScheme in [ColorScheme.light, .dark] {
            for background in [
                CrestBrandTheme.canvas(colorScheme),
                CrestBrandTheme.surface(colorScheme),
            ] {
                let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                    foreground: CrestBrandTheme.accentText(colorScheme),
                    background: background,
                    colorScheme: colorScheme
                )
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    """
                    A text-only control renders the accent as text, so \
                    accentText must clear WCAG AA in \(colorScheme).
                    """
                )
            }
        }

        assertSameResolvedColor(
            CrestBrandTheme.accentText,
            CrestBrandTheme.accentText(.light),
            colorScheme: .light
        )
        assertSameResolvedColor(
            CrestBrandTheme.accentText,
            CrestBrandTheme.accentText(.dark),
            colorScheme: .dark
        )
        XCTAssertEqual(
            CrestBrandTheme.accentTextLightComponents,
            .init(red: 178, green: 64, blue: 47)
        )
        XCTAssertEqual(
            CrestBrandTheme.accentTextDarkComponents,
            .init(red: 250, green: 120, blue: 101)
        )
    }

    func testPrimaryCapsuleKeepsInkLegibleOnButterInBothSchemes() {
        // The butter fill is a fixed brand hue, so the primary capsule does not flip
        // with the scheme. It still has to be readable in either one.
        for colorScheme in [ColorScheme.light, .dark] {
            let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                foreground: CrestBrandPalette.ink,
                background: CrestBrandPalette.butter,
                colorScheme: colorScheme
            )
            XCTAssertGreaterThanOrEqual(ratio, 4.5)
        }
    }

    // MARK: - House palettes

    func testHousePalettesPinOneNineColorHeraldicSet() {
        XCTAssertEqual(
            BrowserSpaceHousePalette.allCases.map(\.name),
            [
                "Winter",
                "Lion",
                "Storm",
                "Dragon",
                "Meadow",
                "Iron",
                "River",
                "Sun",
                "Vigil"
            ]
        )
        XCTAssertTrue(BrowserSpaceHousePalette.allCases.allSatisfy {
            $0.colors.count == BrowserSpaceBranding.maximumColorCount
        })

        assertPalette(
            .winter,
            field: (0.118, 0.157, 0.200),
            primary: (0.243, 0.306, 0.369),
            accent: (0.525, 0.678, 0.769)
        )
        assertPalette(
            .lion,
            field: (0.235, 0.055, 0.102),
            primary: (0.447, 0.125, 0.188),
            accent: (0.788, 0.635, 0.329)
        )
        assertPalette(
            .storm,
            field: (0.082, 0.094, 0.141),
            primary: (0.192, 0.220, 0.282),
            accent: (0.690, 0.561, 0.290)
        )
        assertPalette(
            .dragon,
            field: (0.102, 0.063, 0.051),
            primary: (0.478, 0.118, 0.071),
            accent: (0.745, 0.267, 0.220)
        )
        assertPalette(
            .meadow,
            field: (0.082, 0.137, 0.094),
            primary: (0.204, 0.341, 0.220),
            accent: (0.737, 0.655, 0.400)
        )
        assertPalette(
            .iron,
            field: (0.055, 0.102, 0.110),
            primary: (0.173, 0.227, 0.235),
            accent: (0.612, 0.592, 0.506)
        )
        assertPalette(
            .river,
            field: (0.059, 0.118, 0.180),
            primary: (0.133, 0.282, 0.424),
            accent: (0.659, 0.361, 0.255)
        )
        assertPalette(
            .sun,
            field: (0.208, 0.086, 0.043),
            primary: (0.545, 0.239, 0.106),
            accent: (0.816, 0.620, 0.396)
        )
        assertPalette(
            .vigil,
            field: (0.063, 0.067, 0.071),
            primary: (0.153, 0.165, 0.180),
            accent: (0.482, 0.514, 0.549)
        )
    }

    func testEveryHousePaletteResolvesOneLightForeground() {
        // Each palette is value-coherent on purpose: field, primary, and charge
        // all sit below the flip point, so the sidebar keeps one text tone across
        // the whole banner whether or not the reader keeps the readability fade.
        for palette in BrowserSpaceHousePalette.allCases {
            for fade in [0.0, BrowserSpaceBranding.initialReadabilityFade] {
                let branding = BrowserSpaceBranding(
                    colors: palette.colors,
                    readabilityFade: fade
                )
                XCTAssertEqual(
                    BrowserSpaceForegroundPolicy.tone(for: branding),
                    .light,
                    "\(palette.name) must carry light content at fade \(fade)."
                )
            }
        }
    }

    func testHousePaletteFieldsAndPrimariesClearTextContrastWithoutTheFade() {
        // Worst case for a light foreground is a reader who turned the
        // readability fade off, so the two colors that carry sidebar text have to
        // clear WCAG AA against white on their own.
        for palette in BrowserSpaceHousePalette.allCases {
            for (label, color) in [
                ("field", palette.colors[0]),
                ("primary", palette.colors[1])
            ] {
                let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                    foreground: .white,
                    background: color.color,
                    colorScheme: .dark
                )
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(palette.name) \(label) must clear AA text contrast (got \(ratio))."
                )
                XCTAssertEqual(
                    BrowserVisualAccessibilityPolicy.readableForeground(
                        over: color.color,
                        colorScheme: .dark
                    ),
                    .white
                )
            }
        }
    }

    func testHousePaletteChargesClearTheNonTextMinimumAsRendered() {
        // The charge is the one bright tincture in each palette. It only ever
        // carries symbols and banner bands, so it answers to the 3:1 non-text
        // minimum, measured the way the banner actually renders it — at the fade
        // Crest seeds Spaces with and at the lower fade a plain branding starts
        // from.
        for palette in BrowserSpaceHousePalette.allCases {
            for branding in [
                BrowserSpaceBranding(colors: palette.colors),
                BrowserSpaceBranding(
                    colors: palette.colors,
                    readabilityFade: BrowserSpaceBranding.initialReadabilityFade
                )
            ] {
                let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                    foreground: .white,
                    background: renderedBannerColor(palette.colors[2], in: branding),
                    colorScheme: .dark
                )
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    3.0,
                    """
                    \(palette.name) charge must clear the non-text minimum at fade \
                    \(branding.readabilityFade) (got \(ratio)).
                    """
                )
            }
        }
    }

    func testHousePalettesHoldOneRestrainedValueLadder() {
        // Modern heraldry, not costume: every palette climbs field → primary →
        // charge, and no two palettes share a field.
        var fields: Set<BrowserSpaceBrandColor> = []
        for palette in BrowserSpaceHousePalette.allCases {
            let luminances = palette.colors.map(relativeLuminance)
            XCTAssertLessThan(
                luminances[0],
                luminances[1],
                "\(palette.name) primary must sit a value step above its field."
            )
            XCTAssertLessThan(
                luminances[1],
                luminances[2],
                "\(palette.name) charge must sit a value step above its primary."
            )
            XCTAssertLessThan(
                luminances[0],
                0.03,
                "\(palette.name) field must stay deep enough to read as a field."
            )
            XCTAssertTrue(
                fields.insert(palette.colors[0]).inserted,
                "\(palette.name) repeats another palette's field."
            )
        }
    }

    private func assertPalette(
        _ palette: BrowserSpaceHousePalette,
        field: (Double, Double, Double),
        primary: (Double, Double, Double),
        accent: (Double, Double, Double),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            palette.colors,
            [
                BrowserSpaceBrandColor(red: field.0, green: field.1, blue: field.2),
                BrowserSpaceBrandColor(red: primary.0, green: primary.1, blue: primary.2),
                BrowserSpaceBrandColor(red: accent.0, green: accent.1, blue: accent.2)
            ],
            file: file,
            line: line
        )
    }

    private func renderedBannerColor(
        _ color: BrowserSpaceBrandColor,
        in branding: BrowserSpaceBranding
    ) -> Color {
        // Mirrors BrowserSpaceBannerBackground: the field paints at banner
        // strength over black, then the readability fade lays a black scrim on top.
        let overlay = min(branding.readabilityFade * 0.55, 0.7)
        let strength = branding.bannerStrength
        func channel(_ value: Double) -> Double {
            value * strength * (1 - overlay)
        }
        return Color(
            red: channel(color.red),
            green: channel(color.green),
            blue: channel(color.blue)
        )
    }

    private func relativeLuminance(of color: BrowserSpaceBrandColor) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private func assertSameResolvedColor(
        _ dynamicColor: Color,
        _ expected: Color,
        colorScheme: ColorScheme,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let resolvedDynamic = dynamicColor.resolve(in: environment)
        let resolvedExpected = expected.resolve(in: environment)
        XCTAssertEqual(
            Double(resolvedDynamic.red),
            Double(resolvedExpected.red),
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(resolvedDynamic.green),
            Double(resolvedExpected.green),
            accuracy: 0.01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Double(resolvedDynamic.blue),
            Double(resolvedExpected.blue),
            accuracy: 0.01,
            file: file,
            line: line
        )
    }
}
