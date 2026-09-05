import SwiftUI

/// The sidebar row rules that follow from what the shell can do.
///
/// Every rule reads `BrowserInteractionCapabilities` and nothing else, so a
/// row never asks which target compiled it and a shell that gains or loses an
/// input changes its rows by changing one value at the root.
enum BrowserSidebarInteractionPolicy {
    /// Whether a row may keep its trailing control hidden until the pointer
    /// arrives over it.
    ///
    /// Hide-until-hover is only safe where hover exists *and* touch does not:
    /// a finger has no way to ask a row to reveal anything, so a control that
    /// waits for hover is simply unreachable there. An attached trackpad does
    /// not buy the trade back, because the same row still has to answer to a
    /// finger.
    static func revealsRowControlsOnHoverOnly(
        _ capabilities: BrowserInteractionCapabilities
    ) -> Bool {
        capabilities.supportsHover && !capabilities.supportsTouch
    }

    /// The geometry and reveal behavior of a row's trailing close or unload
    /// control.
    ///
    /// Touch decides this rather than hover: the control has to be hittable by
    /// the least precise input the shell accepts, and a control sized for a
    /// finger is also the one that has to stay on screen.
    static func trailingControlMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserTabTrailingControlMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The layout a tab row draws itself with.
    ///
    /// Touch decides this for the same reason it decides the trailing control:
    /// the insets, the favicon column, and the height behaviour all follow
    /// from the least precise input the shell accepts.
    static func tabRowMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarTabRowMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The layout a stacked split-group row draws its container with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// grouped surface has to hold rows a finger can tell apart, and the
    /// header above them has to be legible at the same distance.
    static func splitGroupRowMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarSplitGroupRowMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The layout a saved folder's header draws itself with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// symbol column, the trailing inset, and the height behaviour all follow
    /// from the least precise input the shell accepts, and the header has to
    /// sit in the same column as the rows it opens onto.
    static func savedFolderHeaderMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserFolderHeaderMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's new-tab row draws itself with.
    ///
    /// Touch decides this like it decides the rows below it: the row is a hit
    /// target, its height has to be able to grow with the label, and the hover
    /// surface a pointer shell rests under it is not a treatment a finger can
    /// ask for.
    static func newTabRowMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarNewTabRowMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The geometry the tab list's own furniture draws itself with — the seam
    /// between the saved and current runs, and the band an empty run keeps for
    /// a drop.
    ///
    /// Touch decides this too. The seam carries a control that only a pointer
    /// can reveal, and the band has to be big enough for the least precise
    /// input the shell accepts to land in.
    static func tabListMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarTabListMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's address field draws itself with.
    ///
    /// Touch decides this like it decides the rows: the field is a hit target
    /// before it is a label, so its band, its gutter, and the controls inside
    /// it are all sized for the least precise input the shell accepts.
    static func addressFieldMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarAddressFieldMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's navigation strip draws itself with.
    ///
    /// Touch decides this too. The back, forward, and reload controls sit
    /// shoulder to shoulder, so the least precise input the shell accepts is
    /// what sets both their targets and the gaps between them.
    static func navigationControlMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSidebarNavigationControlMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The layout the Space header draws itself with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// icon, the disclosure chevron, and the actions menu all have to answer
    /// to the least precise input the shell accepts, and a menu sized for a
    /// finger is also the one whose row can no longer be a fixed band.
    static func spaceHeaderMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSpaceHeaderMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// The geometry one Space's segment in the switcher draws itself with.
    ///
    /// Touch decides this like everything else the reader has to aim at: the
    /// crest is the target, so it is sized for the least precise input the
    /// shell accepts.
    static func spacePickerMetrics(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSpacePickerMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    /// How the Space switcher lays its Spaces out.
    ///
    /// Touch decides the arrangement rather than the styling, because the two
    /// arrangements answer different questions. Segments a finger can hit stop
    /// fitting side by side after a handful of Spaces, so a touch shell needs
    /// a track that scrolls and centres the selection. A pointer shell keeps
    /// every Space on screen at once and spends the room it saves on the
    /// accessories that flank the strip.
    static func spaceSwitcherArrangement(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserSpaceSwitcherArrangement {
        capabilities.supportsTouch ? .scrollingSegments : .compactStrip
    }

    /// Whether a row anchors the surface that grows out of it with a
    /// matched-geometry destination.
    ///
    /// Two things have to be true, and neither implies the other. There must be
    /// a pairing to join at all — `pairsRowWithPromotedSurface` — and the shell
    /// must not already be joining it through the system's navigation zoom,
    /// which registers the row as that transition's source under the same
    /// identity. Two anchors on one identity are two answers to the same
    /// question.
    ///
    /// Reading this as "anything but the native zoom" is what broke the compact
    /// shell's reorder lift: its floating and regular placements have no pairing
    /// *and* no native zoom, so every row was handed a partnerless geometry
    /// anchor — a presentation transform sitting over the view
    /// `BrowserPlatformTabDragSourceModifier` hands to the system drag
    /// interaction. The tab viewer, which does use the native zoom, kept
    /// lifting; those two placements stopped.
    static func usesMatchedGeometryPromotionDestination(
        _ capabilities: BrowserInteractionCapabilities
    ) -> Bool {
        capabilities.pairsRowWithPromotedSurface
            && !capabilities.usesNativeNavigationTransition
    }

    /// The height a tab row may not fall below.
    ///
    /// The accessibility bump is keyed on touch, not on the text size alone: a
    /// pointer shell holds its rows to one exact height so the list stays a
    /// scannable column, while a touch row is already a hit target and has to
    /// grow with the label rather than clip it.
    static func rowMinHeight(
        _ capabilities: BrowserInteractionCapabilities,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        guard capabilities.supportsTouch, dynamicTypeSize.isAccessibilitySize
        else { return CrestLayout.sidebarRowHeight }
        return accessibilityTouchRowHeight
    }

    /// Whether a split group's member lines must keep the full tab-row height.
    ///
    /// Compressing members so a group reads as one row rather than several is
    /// a trade a pointer shell is free to make: it costs precision the pointer
    /// has to spare. A finger does not, so a touch shell is held to the full
    /// height and lets the container surface and the count affordance carry
    /// the grouping instead. Both shells draw members at full height today;
    /// the rule is what keeps the compact one there.
    static func splitMembersUseFullRowHeight(
        _ capabilities: BrowserInteractionCapabilities
    ) -> Bool {
        capabilities.supportsTouch
    }

    /// The floor a touch row grows to once the reader has chosen an
    /// accessibility text size, which no longer fits the resting row height.
    static let accessibilityTouchRowHeight: CGFloat = 56
}

/// The trailing control's drawn geometry, resolved once per shell rather than
/// spelled out by each row.
///
/// `controlSize` is the frame the button claims — the hit target — and
/// `glyphSize` the point size of the symbol inside it. The two are separate
/// because a touch target grows well past the glyph it contains.
struct BrowserTabTrailingControlMetrics: Equatable, Sendable {
    let controlSize: CGSize
    let glyphSize: CGFloat
    let glyphWeight: Font.Weight

    /// Whether the control stays on screen regardless of hover and selection.
    let isAlwaysVisible: Bool

    /// The opacity a visible close control rests at on a row that is not
    /// selected.
    ///
    /// A shell that hides the control until it is asked for has already made
    /// the control deliberate by the time it is drawn, so it draws at full
    /// strength. A shell that cannot hide it has an xmark on every row at all
    /// times instead, and holding the unselected ones back is what keeps the
    /// list reading as titles rather than as a column of close buttons.
    let restingCloseOpacity: CGFloat

    /// Whether the control wears the chrome's hover-and-press treatment.
    ///
    /// That treatment is a response to a pointer resting on the control, which
    /// is exactly what a touch shell has no way to show; there the button is
    /// drawn plain and the press is the system's own.
    let usesChromeControlStyle: Bool

    /// A pointer shell: the chrome control size, a light glyph, and a control
    /// that waits for hover or selection before it appears.
    ///
    /// The target stays tied to `CrestLayout.minimumHitTarget` rather than to a
    /// number, because every other pointer control in the chrome is sized from
    /// that token and the row has no reason to be the one that drifts.
    static let pointer = BrowserTabTrailingControlMetrics(
        controlSize: CGSize(
            width: CrestLayout.minimumHitTarget,
            height: CrestLayout.minimumHitTarget
        ),
        glyphSize: 12,
        glyphWeight: .regular,
        isAlwaysVisible: false,
        restingCloseOpacity: 1,
        usesChromeControlStyle: true
    )

    /// A touch shell: a full 44pt target and a heavier glyph to read at that
    /// size, always drawn because nothing can reveal it.
    static let touch = BrowserTabTrailingControlMetrics(
        controlSize: CGSize(width: 44, height: 44),
        glyphSize: 14,
        glyphWeight: .medium,
        isAlwaysVisible: true,
        restingCloseOpacity: 0.65,
        usesChromeControlStyle: false
    )

    /// Whether the control is drawn at all, given what the row can tell the
    /// reader about itself right now.
    ///
    /// Selection counts alongside hover because the selected row is the one a
    /// reader is most likely to want to close, and it is the one row a pointer
    /// shell can reveal the control on without a pointer being there.
    func isRevealed(isHovering: Bool, isSelected: Bool) -> Bool {
        isAlwaysVisible || isHovering || isSelected
    }

    /// The opacity a revealed close control draws at.
    func closeOpacity(isSelected: Bool) -> CGFloat {
        isSelected ? 1 : restingCloseOpacity
    }
}
