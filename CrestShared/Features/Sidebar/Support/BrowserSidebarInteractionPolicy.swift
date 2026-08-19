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
        isAlwaysVisible: false
    )

    /// A touch shell: a full 44pt target and a heavier glyph to read at that
    /// size, always drawn because nothing can reveal it.
    static let touch = BrowserTabTrailingControlMetrics(
        controlSize: CGSize(width: 44, height: 44),
        glyphSize: 14,
        glyphWeight: .medium,
        isAlwaysVisible: true
    )
}
