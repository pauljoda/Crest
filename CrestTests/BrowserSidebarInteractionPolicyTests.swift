import SwiftUI
import XCTest

@testable import Crest

final class BrowserSidebarInteractionPolicyTests: XCTestCase {

    // MARK: - Shared icon customization

    func testAutomaticWebsiteFaviconDoesNotOfferAResetAction() {
        let tab = BrowserTab(
            title: "Example",
            url: URL(string: "https://example.com"),
            faviconData: Data([0x01]),
            iconMode: .automatic,
            placement: .current
        )

        XCTAssertFalse(BrowserTabIconCustomizationPolicy.showsReset(for: tab))
    }

    func testOnlyDeliberateTabIconOverridesOfferAResetAction() {
        let pulled = BrowserTab(
            title: "Pulled",
            url: URL(string: "https://example.com/pulled"),
            faviconData: Data([0x01]),
            iconMode: .pulled,
            placement: .current
        )
        let emoji = BrowserTab(
            title: "Emoji",
            url: URL(string: "https://example.com/emoji"),
            symbol: BrowserTab.symbol(forEmoji: "👩🏽‍💻"),
            iconMode: .emoji,
            placement: .current
        )

        XCTAssertTrue(BrowserTabIconCustomizationPolicy.showsReset(for: pulled))
        XCTAssertTrue(BrowserTabIconCustomizationPolicy.showsReset(for: emoji))
    }

    func testCompactIconPickerLetsTheSystemChooseAVerticalEdge() {
        XCTAssertNil(
            BrowserIconPopoverPlacementPolicy.preferredArrowEdge(
                horizontalSizeClass: .compact,
                regularArrowEdge: .trailing
            )
        )
        XCTAssertEqual(
            BrowserIconPopoverPlacementPolicy.preferredArrowEdge(
                horizontalSizeClass: .regular,
                regularArrowEdge: .trailing
            ),
            .trailing
        )
    }

    // MARK: - Hiding a control until the pointer arrives

    /// The full matrix, because the rule is a conjunction and only one of the
    /// four combinations may hide anything. The touch-and-hover corner is the
    /// one that matters: an iPad with a trackpad reports both, and treating
    /// hover as sufficient there would leave the close control unreachable for
    /// the finger that is still the primary input.
    func testControlsHideUntilHoverOnlyWhereHoverExistsAndTouchDoesNot() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: true, touch: false)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: true, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: false, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: false, touch: false)
            )
        )
    }

    // MARK: - Trailing control metrics

    /// Pins the numbers the macOS sidebar rows draw today. The hit target is
    /// asserted against both the literal and the token so a change to either
    /// one alone fails here rather than silently resizing every row.
    func testPointerMetricsMatchTheWindowedSidebarRow() {
        let metrics = BrowserSidebarInteractionPolicy.trailingControlMetrics(
            capabilities(hover: true, touch: false)
        )

        XCTAssertEqual(metrics.controlSize, CGSize(width: 28, height: 28))
        XCTAssertEqual(metrics.controlSize.width, CrestLayout.minimumHitTarget)
        XCTAssertEqual(metrics.glyphSize, 12)
        XCTAssertEqual(metrics.glyphWeight, .regular)
        XCTAssertFalse(metrics.isAlwaysVisible)
        XCTAssertEqual(metrics.restingCloseOpacity, 1)
        XCTAssertTrue(metrics.usesChromeControlStyle)
    }

    /// Pins the numbers the compact sidebar rows draw today. They are literals
    /// rather than tokens on purpose: this suite is hosted on macOS, where the
    /// platform hit target is 28, and the touch profile still has to be 44.
    func testTouchMetricsMatchTheCompactSidebarRow() {
        let metrics = BrowserSidebarInteractionPolicy.trailingControlMetrics(
            capabilities(hover: false, touch: true)
        )

        XCTAssertEqual(metrics.controlSize, CGSize(width: 44, height: 44))
        XCTAssertEqual(metrics.glyphSize, 14)
        XCTAssertEqual(metrics.glyphWeight, .medium)
        XCTAssertTrue(metrics.isAlwaysVisible)
        XCTAssertEqual(metrics.restingCloseOpacity, 0.65)
        XCTAssertFalse(metrics.usesChromeControlStyle)
    }

    // MARK: - Revealing and dimming the trailing control

    /// A pointer row hides its control at rest and shows it once the row can
    /// say something about itself: the pointer is over it, or it is the
    /// selected row. A touch row cannot hide anything, so every combination
    /// answers the same way.
    func testRevealMatrixFollowsTheShellRatherThanTheRow() {
        let pointer = BrowserTabTrailingControlMetrics.pointer
        XCTAssertFalse(pointer.isRevealed(isHovering: false, isSelected: false))
        XCTAssertTrue(pointer.isRevealed(isHovering: true, isSelected: false))
        XCTAssertTrue(pointer.isRevealed(isHovering: false, isSelected: true))

        let touch = BrowserTabTrailingControlMetrics.touch
        XCTAssertTrue(touch.isRevealed(isHovering: false, isSelected: false))
        XCTAssertTrue(touch.isRevealed(isHovering: true, isSelected: false))
        XCTAssertTrue(touch.isRevealed(isHovering: false, isSelected: true))
    }

    /// The exact opacities each shell draws a revealed close control at. A
    /// pointer control has already been asked for by the time it appears, so
    /// it never rests dim; a touch control is on every row at once and holds
    /// the unselected ones back.
    func testOnlyAnAlwaysVisibleCloseControlDimsOnAnUnselectedRow() {
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.pointer.closeOpacity(isSelected: false),
            1
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.pointer.closeOpacity(isSelected: true),
            1
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.touch.closeOpacity(isSelected: false),
            0.65
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.touch.closeOpacity(isSelected: true),
            1
        )
    }

    // MARK: - Row layout

    /// Pins the geometry each shell's rows draw today, so a change to either
    /// profile fails here rather than quietly shifting every title in the
    /// sidebar by a couple of points.
    func testRowLayoutFollowsTheLeastPreciseInputTheShellAccepts() {
        let pointer = BrowserSidebarInteractionPolicy.tabRowMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.contentSpacing, 0)
        XCTAssertEqual(pointer.contentLeadingInset, 9)
        XCTAssertEqual(pointer.contentTrailingInset, 9)
        XCTAssertEqual(pointer.surfaceHorizontalInset, 8)
        XCTAssertNil(pointer.faviconSlot)
        XCTAssertTrue(pointer.fillsRowHeight)

        let touch = BrowserSidebarInteractionPolicy.tabRowMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.contentSpacing, 4)
        XCTAssertEqual(touch.contentLeadingInset, 12)
        XCTAssertEqual(touch.contentTrailingInset, 4)
        XCTAssertEqual(touch.surfaceHorizontalInset, 8)
        XCTAssertEqual(
            touch.faviconSlot,
            BrowserSidebarTabFaviconSlot(width: 20, glyphSize: 17, glyphWeight: .medium)
        )
        XCTAssertFalse(touch.fillsRowHeight)
    }

    /// A trackpad beside a touchscreen must not tighten the row back down.
    func testAddingHoverToATouchShellKeepsTheTouchRowLayout() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Address field layout

    /// Pins the geometry each shell's address field draws today, which is what
    /// two forks of the field used to disagree about. The corner radius is
    /// asserted against the same token on both sides on purpose: the two forks
    /// spelled it differently — one through the chrome layout, one through the
    /// sidebar control token — and they have always resolved to one number.
    func testAddressFieldGeometryFollowsTheShell() {
        let pointer = BrowserSidebarInteractionPolicy.addressFieldMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.contentSpacing, 7)
        XCTAssertEqual(pointer.horizontalPadding, 9)
        XCTAssertEqual(pointer.height, 36)
        XCTAssertFalse(pointer.growsWithContent)
        XCTAssertEqual(pointer.cornerRadius, CrestRadius.compact)
        XCTAssertEqual(pointer.editingRingWidth, 0.5)
        XCTAssertEqual(pointer.leadingGlyphSlot, 28)

        let touch = BrowserSidebarInteractionPolicy.addressFieldMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.contentSpacing, 8)
        XCTAssertEqual(touch.horizontalPadding, 12)
        XCTAssertEqual(touch.height, 44)
        XCTAssertTrue(touch.growsWithContent)
        XCTAssertEqual(touch.cornerRadius, CrestRadius.compact)
        XCTAssertEqual(touch.editingRingWidth, 1)
        XCTAssertNil(touch.leadingGlyphSlot)
    }

    /// Only a touch shell enlarges the clear control, because only there is it
    /// aimed at with a finger. A pointer shell names no font at all rather than
    /// naming the inherited one, so the control keeps whatever the field is
    /// drawn in.
    func testOnlyATouchShellSizesTheClearControlForAFinger() {
        XCTAssertNil(
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: true, touch: false)
            ).clearControlFont
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: false, touch: true)
            ).clearControlFont,
            .system(size: 15, weight: .medium)
        )
    }

    /// Only a touch shell lets the field grow past its resting band. The
    /// windowed sidebar's chrome strip has to stay one unchanging height no
    /// matter how large the reader's text is.
    func testOnlyATouchAddressFieldGrowsPastItsRestingBand() {
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: true, touch: false)
            ).growsWithContent
        )
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: false, touch: true)
            ).growsWithContent
        )
    }

    /// A trackpad beside a touchscreen must not tighten the field back down.
    func testAddingHoverToATouchShellKeepsTheTouchAddressField() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.addressFieldMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    /// The leading glyph and the site control it gives way to occupy the same
    /// square on the pointer shell, which is what keeps the address from
    /// shifting sideways as the two swap.
    func testThePointerLeadingGlyphReservesTheSiteControlSquare() {
        XCTAssertEqual(
            BrowserSidebarAddressFieldMetrics.pointer.leadingGlyphSlot,
            BrowserAddressSecurityControlPolicy.controlSize
        )
    }

    // MARK: - Navigation strip layout

    /// Pins the geometry each shell's back, forward, and reload strip draws
    /// today, which is the other thing two forks of the strip used to disagree
    /// about.
    func testNavigationStripGeometryFollowsTheShell() {
        let pointer = BrowserSidebarInteractionPolicy.navigationControlMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.controlSpacing, 1)
        XCTAssertEqual(pointer.leadingSpacerMinimum, 8)
        XCTAssertEqual(pointer.controlSize, CGSize(width: 30, height: 30))
        XCTAssertEqual(
            pointer.reloadMenuControlSize,
            CGSize(width: 18, height: 30)
        )
        XCTAssertEqual(pointer.reloadSymbolPointSize, 15)
        XCTAssertEqual(pointer.leadingInset, 0)
        XCTAssertEqual(pointer.trailingInset, 12)
        XCTAssertEqual(pointer.barHeight, 48)
        XCTAssertFalse(pointer.growsWithContent)
        XCTAssertEqual(pointer.accessibilityVerticalPadding, 0)

        let touch = BrowserSidebarInteractionPolicy.navigationControlMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.controlSpacing, 2)
        XCTAssertEqual(touch.leadingSpacerMinimum, 0)
        XCTAssertEqual(touch.controlSize, CGSize(width: 44, height: 44))
        XCTAssertEqual(
            touch.reloadMenuControlSize,
            CGSize(width: 28, height: 44)
        )
        XCTAssertEqual(touch.reloadSymbolPointSize, 14)
        XCTAssertEqual(touch.leadingInset, 14)
        XCTAssertEqual(touch.trailingInset, 14)
        XCTAssertEqual(touch.barHeight, 48)
        XCTAssertTrue(touch.growsWithContent)
        XCTAssertEqual(touch.accessibilityVerticalPadding, 8)
    }

    /// The two shells draw the chevrons at different sizes and weights. Pinned
    /// here because the strip reads them from the profile rather than naming
    /// them, and a swap would be silent.
    func testNavigationChevronsAreSizedForTheShellTheyAreAimedAtWith() {
        XCTAssertEqual(
            BrowserSidebarNavigationControlMetrics.pointer.historySymbolFont,
            .system(size: 15, weight: .regular)
        )
        XCTAssertEqual(
            BrowserSidebarNavigationControlMetrics.touch.historySymbolFont,
            .system(size: 17, weight: .medium)
        )
    }

    /// A trackpad beside a touchscreen must not tighten the strip back down.
    func testAddingHoverToATouchShellKeepsTheTouchNavigationStrip() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.navigationControlMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.navigationControlMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Space header layout

    /// Pins the geometry each shell's Space header draws today, which is what
    /// two forks of this header used to disagree about. The actions target is
    /// asserted as a literal on both sides: the suite is hosted on macOS,
    /// where the platform hit target is 28, and neither 24 nor 44 may follow
    /// it.
    func testSpaceHeaderGeometryFollowsTheLeastPreciseInputTheShellAccepts() {
        let pointer = BrowserSidebarInteractionPolicy.spaceHeaderMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.disclosureGlyphSize, 9)
        XCTAssertEqual(pointer.iconSize, 20)
        XCTAssertEqual(pointer.actionsControlSize, 24)
        XCTAssertNil(pointer.actionsGlyph)
        XCTAssertTrue(pointer.fillsRowHeight)
        XCTAssertFalse(pointer.expandsActionsHitArea)

        let touch = BrowserSidebarInteractionPolicy.spaceHeaderMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.disclosureGlyphSize, 10)
        XCTAssertEqual(touch.iconSize, 22)
        XCTAssertEqual(touch.actionsControlSize, 44)
        XCTAssertEqual(
            touch.actionsGlyph,
            BrowserSpaceHeaderActionsGlyph(size: 17, weight: .medium)
        )
        XCTAssertFalse(touch.fillsRowHeight)
        XCTAssertTrue(touch.expandsActionsHitArea)
    }

    /// Only a header held to one exact height stretches its title to fill it.
    /// Everywhere else the ceiling comes from the pinned-chrome policy, which
    /// leaves the row at its intrinsic height so a long name can wrap rather
    /// than clip.
    func testOnlyAFixedBandHeaderStretchesItsTitleToTheRowHeight() {
        XCTAssertEqual(BrowserSpaceHeaderMetrics.pointer.contentMaxHeight, .infinity)
        XCTAssertEqual(
            BrowserSpaceHeaderMetrics.touch.contentMaxHeight,
            BrowserSidebarScrollLayoutPolicy.fixedSpaceHeaderMaxHeight
        )
    }

    /// A trackpad beside a touchscreen must not shrink the header's menu back
    /// down to a pointer target.
    func testAddingHoverToATouchShellKeepsTheTouchSpaceHeader() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.spaceHeaderMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.spaceHeaderMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Space switcher

    /// The arrangement, not the styling, is what the two switchers disagreed
    /// about. Segments a finger can hit stop fitting side by side after a
    /// handful of Spaces, so a touch shell scrolls; a pointer shell keeps them
    /// all on screen and spends the room on its accessories.
    func testTheSpaceSwitcherScrollsExactlyWhereTheShellAcceptsTouch() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.spaceSwitcherArrangement(
                capabilities(hover: true, touch: false)
            ),
            .compactStrip
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.spaceSwitcherArrangement(
                capabilities(hover: false, touch: true)
            ),
            .scrollingSegments
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.spaceSwitcherArrangement(
                capabilities(hover: true, touch: true)
            ),
            .scrollingSegments
        )
    }

    /// Pins the crest geometry each shell's segments draw today.
    func testSpacePickerSegmentsAreSizedForTheAimTheShellAccepts() {
        let pointer = BrowserSidebarInteractionPolicy.spacePickerMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.iconSize, 24)
        XCTAssertEqual(pointer.lockSize, 6)
        XCTAssertEqual(pointer.iconPadding, 0)

        let touch = BrowserSidebarInteractionPolicy.spacePickerMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.iconSize, 30)
        XCTAssertEqual(touch.lockSize, 7)
        XCTAssertEqual(touch.iconPadding, 4)
    }

    /// A pointer crest has to fit inside the compact picker's own segment, or
    /// the strip stops being compact. A touch crest plus its clearance is what
    /// defines the scrolling track's step instead, so it must not exceed it.
    func testEachSegmentFitsTheTrackItsArrangementDrawsItIn() {
        let pointer = BrowserSpacePickerMetrics.pointer
        XCTAssertLessThanOrEqual(
            pointer.iconSize + 2 * pointer.iconPadding,
            BrowserSpaceSwitcherLayout.segmentWidth
        )
        XCTAssertLessThanOrEqual(
            pointer.iconSize + 2 * pointer.iconPadding,
            BrowserSpaceSwitcherLayout.segmentHeight
        )

        let touch = BrowserSpacePickerMetrics.touch
        XCTAssertLessThanOrEqual(
            touch.iconSize + 2 * touch.iconPadding,
            BrowserSpaceSwitcherLayout.scrollingSegmentExtent
        )
    }

    /// A trackpad beside a touchscreen must not shrink the crest back down.
    func testAddingHoverToATouchShellKeepsTheTouchSpaceSegment() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.spacePickerMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.spacePickerMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Promotion anchoring

    /// The two anchors are alternatives, not a pair: a shell that zooms the
    /// page in with the system's own transition registers the row there, and
    /// a matched-geometry destination under the same identity would be a
    /// second answer to the same question.
    func testOnlyAShellWithoutTheNativeZoomAnchorsWithMatchedGeometry() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
                BrowserInteractionCapabilities()
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
                BrowserInteractionCapabilities(usesNativeNavigationTransition: true)
            )
        )
    }

    /// Not having the native zoom is not the same as having a pairing. A shell
    /// can have neither, and the whole matrix has to say so — reading the rule
    /// as "anything but the native zoom" handed a partnerless matched-geometry
    /// anchor to every row on the compact shell's floating and regular
    /// placements, which is the view the system drag interaction lifts, and the
    /// reorder lift stopped starting there while the tab viewer kept working.
    func testARowAnchorsNothingWhereNoSurfaceGrowsOutOfIt() {
        let matrix: [(pairs: Bool, native: Bool, anchorsWithGeometry: Bool)] = [
            (pairs: true, native: false, anchorsWithGeometry: true),
            (pairs: true, native: true, anchorsWithGeometry: false),
            (pairs: false, native: false, anchorsWithGeometry: false),
            (pairs: false, native: true, anchorsWithGeometry: false),
        ]

        for entry in matrix {
            XCTAssertEqual(
                BrowserSidebarInteractionPolicy
                    .usesMatchedGeometryPromotionDestination(
                        BrowserInteractionCapabilities(
                            usesNativeNavigationTransition: entry.native,
                            pairsRowWithPromotedSurface: entry.pairs
                        )
                    ),
                entry.anchorsWithGeometry,
                "pairs: \(entry.pairs), native zoom: \(entry.native)"
            )
        }
    }

    /// The windowed shell's own answer, spelled out rather than inherited: its
    /// start page's palette rises out of the row that opened it, so its rows do
    /// carry the matched-geometry end of that pairing.
    func testTheWindowedShellStillPairsItsRowsWithTheSurfaceTheyGrow() {
        XCTAssertTrue(BrowserInteractionCapabilities().pairsRowWithPromotedSurface)
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
                BrowserInteractionCapabilities()
            )
        )
    }

    // MARK: - The anchor a pinned tile claims

    /// A pinned tile is a drag source too, and it reaches the same modifier by a
    /// different route — its own helper rather than the row's pairing of
    /// destination and platform source. That route kept reading the rule as
    /// "anything but the native zoom" long after the row's stopped, so the whole
    /// matrix has to say what a tile claims, not just the row.
    ///
    /// The native-zoom arm is deliberately narrower than the geometry arm: only
    /// the tile the page is actually zooming out of is that transition's source.
    func testAPinnedTileClaimsAnAnchorOnlyWhereThereIsOneToPairWith() {
        let matrix:
            [(
                pairs: Bool, native: Bool, isSource: Bool,
                anchor: BrowserPinnedTabPromotionAnchor
            )] = [
                // A windowed shell: a surface really does rise out of the tile.
                (
                    pairs: true, native: false, isSource: true,
                    anchor: .matchedGeometryDestination
                ),
                (
                    pairs: true, native: false, isSource: false,
                    anchor: .matchedGeometryDestination
                ),
                // The native zoom is the pairing, and only for its own source.
                (
                    pairs: false, native: true, isSource: true,
                    anchor: .navigationZoomSource
                ),
                (
                    pairs: false, native: true, isSource: false,
                    anchor: .none
                ),
                // The compact shell's docked and floating sidebars: no pairing
                // and no zoom. This row is the regression.
                (
                    pairs: false, native: false, isSource: true,
                    anchor: .none
                ),
                (
                    pairs: false, native: false, isSource: false,
                    anchor: .none
                ),
            ]

        for entry in matrix {
            XCTAssertEqual(
                BrowserPinnedTabPromotionPolicy.anchor(
                    hasNamespace: true,
                    isTransitionSource: entry.isSource,
                    capabilities: BrowserInteractionCapabilities(
                        usesNativeNavigationTransition: entry.native,
                        pairsRowWithPromotedSurface: entry.pairs
                    )
                ),
                entry.anchor,
                "pairs: \(entry.pairs), native zoom: \(entry.native), "
                    + "source: \(entry.isSource)"
            )
        }
    }

    /// Negative control for the same rule: with the pairing requirement defeated
    /// — the rule read as the bare negation of the native zoom, which is how the
    /// tile's helper read it — the compact shell's docked sidebar hands every
    /// tile a matched-geometry anchor with nothing on the other end of it.
    ///
    /// That anchor is a presentation transform over the exact view the system
    /// drag interaction lifts, which is why a pinned tab could be picked up on
    /// iPad and dropped nowhere at all.
    func testDefeatingThePairingRequirementRestoresThePartnerlessTileAnchor() {
        let compactDockedSidebar = BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            showsRowDropIndicators: true,
            reservesReorderSectionZones: true,
            usesNativeNavigationTransition: false,
            pairsRowWithPromotedSurface: false
        )

        XCTAssertEqual(
            BrowserPinnedTabPromotionPolicy.anchor(
                hasNamespace: true,
                isTransitionSource: false,
                capabilities: compactDockedSidebar
            ),
            .none,
            "The live rule must leave the drag source untransformed."
        )

        let defeated = !compactDockedSidebar.usesNativeNavigationTransition
        XCTAssertTrue(
            defeated,
            "The rule this replaced would have anchored here, which is the "
                + "defect: no pairing exists, so the anchor has no partner."
        )
    }

    /// A tile with no namespace to anchor in claims nothing, whatever the shell
    /// can do. This is the windowed sidebar's own case — it grows no surface out
    /// of a tile and passes no namespace — and it is why the Mac never saw the
    /// defect the compact shell did.
    func testAPinnedTileWithNoNamespaceClaimsNothing() {
        for pairs in [true, false] {
            for native in [true, false] {
                XCTAssertEqual(
                    BrowserPinnedTabPromotionPolicy.anchor(
                        hasNamespace: false,
                        isTransitionSource: true,
                        capabilities: BrowserInteractionCapabilities(
                            usesNativeNavigationTransition: native,
                            pairsRowWithPromotedSurface: pairs
                        )
                    ),
                    .none,
                    "pairs: \(pairs), native zoom: \(native)"
                )
            }
        }
    }

    /// A trackpad beside a touchscreen must not shrink the target back down.
    func testAddingHoverToATouchShellKeepsTheTouchControl() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.trailingControlMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.trailingControlMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Row height

    func testRowsRestAtTheSidebarRowHeightOnEveryShell() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: false),
                dynamicTypeSize: .large
            ),
            CrestLayout.sidebarRowHeight
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: false, touch: true),
                dynamicTypeSize: .large
            ),
            CrestLayout.sidebarRowHeight
        )
    }

    /// The bump is keyed on touch rather than on the text size alone, which is
    /// what keeps the windowed sidebar's rows at one exact height no matter
    /// how large the reader's text is.
    func testOnlyATouchShellGrowsItsRowsAtAnAccessibilityTextSize() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: false, touch: true),
                dynamicTypeSize: .accessibility1
            ),
            56
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: false),
                dynamicTypeSize: .accessibility5
            ),
            CrestLayout.sidebarRowHeight
        )
    }

    // MARK: - Split group container layout

    /// Pins the container geometry each shell's grouped rows draw today, which
    /// is what two forks of this row used to disagree about. The corner radius
    /// is asserted against the member rows' own radius plus the container
    /// padding, because the two have to stay concentric: a focused member's
    /// corners are drawn one padding inside the container's.
    func testSplitGroupContainerGeometryFollowsTheShell() {
        let pointer = BrowserSidebarInteractionPolicy.splitGroupRowMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.rowVerticalInset, 2)
        XCTAssertEqual(pointer.containerPadding, 4)
        XCTAssertEqual(pointer.containerCornerRadius, 12)
        XCTAssertEqual(pointer.memberSpacing, 0)
        XCTAssertEqual(pointer.headerHeight, 30)
        XCTAssertEqual(pointer.headerGlyphSize, 16)
        XCTAssertEqual(pointer.headerSpacing, 7)

        let touch = BrowserSidebarInteractionPolicy.splitGroupRowMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.rowVerticalInset, 2)
        XCTAssertEqual(touch.containerPadding, 4)
        XCTAssertEqual(touch.containerCornerRadius, 12)
        XCTAssertEqual(touch.memberSpacing, 2)
        XCTAssertEqual(touch.headerHeight, 44)
        XCTAssertEqual(touch.headerGlyphSize, 20)
        XCTAssertEqual(touch.headerSpacing, 8)
        XCTAssertGreaterThanOrEqual(
            touch.headerHeight,
            44,
            "The group action header remains a native touch target."
        )
    }

    /// The container and the rows inside it are concentric on both shells, so
    /// a focused member's corners stay parallel to the group's own.
    func testSplitGroupContainerStaysConcentricWithItsMemberRows() {
        for metrics in [
            BrowserSidebarSplitGroupRowMetrics.pointer,
            BrowserSidebarSplitGroupRowMetrics.touch,
        ] {
            XCTAssertEqual(
                metrics.containerCornerRadius - metrics.containerPadding,
                CrestLayout.sidebarControlCornerRadius
            )
        }
    }

    /// The two insets the container borrows rather than chooses. A group has
    /// to start in the same column as the loose tabs above and below it, and
    /// its count glyph has to sit in the same column as the favicons of the
    /// members underneath — so both come from the tab row profile the same
    /// capabilities resolve, not from a number of the container's own.
    func testSplitGroupBorrowsItsEdgeAndHeaderInsetsFromTheTabRow() {
        for shell in [
            capabilities(hover: true, touch: false),
            capabilities(hover: false, touch: true),
            capabilities(hover: true, touch: true),
        ] {
            let tabRow = BrowserSidebarInteractionPolicy.tabRowMetrics(shell)
            XCTAssertEqual(tabRow.surfaceHorizontalInset, 8)
            XCTAssertEqual(
                tabRow.contentLeadingInset,
                shell.supportsTouch ? 12 : 9
            )
        }
    }

    /// A trackpad beside a touchscreen must not tighten the group back down.
    func testAddingHoverToATouchShellKeepsTheTouchSplitGroupContainer() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.splitGroupRowMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.splitGroupRowMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Split group members

    func testOnlyATouchShellKeepsSplitMembersAtFullRowHeight() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: false, touch: true)
            )
        )
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: true, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: true, touch: false)
            )
        )
    }

    /// A member is a real tab row, so it would otherwise draw the insertion
    /// lines its shell asks every row for. It must not: the container owns both
    /// anchors for the run, and a member drawing its own would double the line
    /// above the first member and light one up under every member at once for a
    /// drop aimed at the end of the section.
    @MainActor
    func testAGroupedMemberLeavesTheInsertionLinesToItsContainer() {
        let shell = BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            showsRowDropIndicators: true
        )

        XCTAssertTrue(
            BrowserSidebarTabRowPreviewFixture.configuration(
                capabilities: shell,
                isSplitGroupMember: false
            ).showsDropIndicators
        )
        XCTAssertFalse(
            BrowserSidebarTabRowPreviewFixture.configuration(
                capabilities: shell,
                isSplitGroupMember: true
            ).showsDropIndicators
        )
    }

    // MARK: - New-tab row metrics

    /// Pins the numbers each shell's new-tab row draws today. The two are not
    /// variations on one row: a pointer row is an exact 40pt band with a hover
    /// surface inside an 8pt margin and its label inset 9pt further in, and a
    /// touch row has no surface, keeps the whole 18pt inset as the label's own
    /// margin, and grows from a 44pt floor instead of holding a fixed height.
    func testTheNewTabRowResolvesEachShellsExactGeometry() {
        let pointer = BrowserSidebarInteractionPolicy.newTabRowMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.labelHorizontalInset, 9)
        XCTAssertEqual(pointer.rowHorizontalInset, 8)
        XCTAssertTrue(pointer.usesFixedHeight)
        XCTAssertTrue(pointer.showsHoverSurface)
        XCTAssertTrue(pointer.showsShortcutTooltip)

        let touch = BrowserSidebarInteractionPolicy.newTabRowMetrics(
            capabilities(hover: true, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.labelHorizontalInset, 0)
        XCTAssertEqual(touch.rowHorizontalInset, 18)
        XCTAssertFalse(touch.usesFixedHeight)
        XCTAssertFalse(touch.showsHoverSurface)
        XCTAssertFalse(touch.showsShortcutTooltip)

        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.newTabRowMetrics(
                capabilities(hover: false, touch: true)
            ),
            .touch
        )
    }

    /// The row's height comes from the same floor the tab rows use, so the
    /// new-tab row and the first tab below it never sit on different rhythms —
    /// including once the reader has chosen an accessibility text size.
    func testTheNewTabRowSharesTheRowHeightFloor() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: true),
                dynamicTypeSize: .accessibility1
            ),
            BrowserSidebarInteractionPolicy.accessibilityTouchRowHeight
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: true),
                dynamicTypeSize: .large
            ),
            CrestLayout.sidebarRowHeight
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: false),
                dynamicTypeSize: .accessibility1
            ),
            CrestLayout.sidebarRowHeight
        )
    }

    // MARK: - Tab list furniture metrics

    /// Pins the seam and the landing band. Only a pointer shell carries the
    /// clear control, because the control waits for a pointer to arrive before
    /// it appears, and the band a finger has to land in is more than twice the
    /// height a pointer's insertion line needs.
    func testTheTabListResolvesEachShellsSeamAndLandingBand() {
        let pointer = BrowserSidebarInteractionPolicy.tabListMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.dividerHorizontalInset, 12)
        XCTAssertEqual(pointer.dividerVerticalInset, 3)
        XCTAssertEqual(pointer.clearActionOcclusionWidth, 52)
        XCTAssertTrue(pointer.carriesClearAction)
        XCTAssertEqual(pointer.sectionEndBandHeight, 12)

        let touch = BrowserSidebarInteractionPolicy.tabListMetrics(
            capabilities(hover: true, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.dividerHorizontalInset, 16)
        XCTAssertEqual(touch.dividerVerticalInset, 5)
        XCTAssertEqual(touch.clearActionOcclusionWidth, 0)
        XCTAssertFalse(touch.carriesClearAction)
        XCTAssertEqual(touch.sectionEndBandHeight, 28)
    }

    /// The seam gives up the clear control wherever a finger is an input, for
    /// the same reason every other hover-revealed control does: nothing a touch
    /// shell can do would ever reveal it.
    func testATouchShellGivesUpTheClearAction() {
        for hover in [true, false] {
            let shell = capabilities(hover: hover, touch: true)
            XCTAssertFalse(
                BrowserSidebarInteractionPolicy.tabListMetrics(shell)
                    .carriesClearAction,
                "hover: \(hover)"
            )
            XCTAssertFalse(
                BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                    shell
                ),
                "hover: \(hover)"
            )
        }

        let pointer = capabilities(hover: true, touch: false)
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.tabListMetrics(pointer)
                .carriesClearAction
        )
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                pointer
            )
        )
    }

    // MARK: - Split-group icon deck

    func testSplitGroupIconDeckRaisesTheFocusedMemberAboveItsPeers() {
        let tabs = splitGroupIconTabs()

        XCTAssertEqual(
            BrowserSidebarSplitGroupIconDeck.orderedMembers(
                tabs,
                focusedMemberID: tabs[0].id
            ).map(\.id),
            [tabs[1].id, tabs[2].id, tabs[0].id]
        )
    }

    func testSplitGroupIconDeckAdmitsAFocusedMemberBeyondItsVisibleLimit() {
        let tabs = splitGroupIconTabs()

        XCTAssertEqual(
            BrowserSidebarSplitGroupIconDeck.orderedMembers(
                tabs,
                focusedMemberID: tabs[3].id
            ).map(\.id),
            [tabs[0].id, tabs[1].id, tabs[3].id]
        )
    }

    func testSplitGroupIconDeckKeepsOrdinaryOrderWithoutAFocusedMember() {
        let tabs = splitGroupIconTabs()

        XCTAssertEqual(
            BrowserSidebarSplitGroupIconDeck.orderedMembers(
                tabs,
                focusedMemberID: nil
            ).map(\.id),
            Array(tabs.prefix(3).map(\.id))
        )
    }

    // MARK: - Fixtures

    private func splitGroupIconTabs() -> [BrowserTab] {
        (1...4).map {
            BrowserTab(
                title: "Deck \($0)",
                url: nil,
                placement: .current
            )
        }
    }

    private func capabilities(
        hover: Bool,
        touch: Bool
    ) -> BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: hover,
            supportsTouch: touch
        )
    }
}
