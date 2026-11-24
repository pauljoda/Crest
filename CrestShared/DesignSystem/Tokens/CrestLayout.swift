import CoreGraphics

/// Cross-feature geometry that represents an interaction contract.
enum CrestLayout {
    static let hairline: CGFloat = 1
    static let focusRing: CGFloat = 3
    /// Default drawn diameter for stand-alone Liquid Glass icon controls.
    static let glassIconButtonDiameter: CGFloat = 44
    static let reloadQuarterTurn: CGFloat = 90
    static let pinnedAccentBorderWidth: CGFloat = 2

    /// The least a control gives a pointer to land on.
    static let pointerHitTarget: CGFloat = 28
    /// The least a control gives a finger to land on.
    static let touchHitTarget: CGFloat = 44
    /// The hit target of the platform's own input. A view the shell's
    /// capabilities reach takes `BrowserInteractionCapabilities.minimumHitTarget`
    /// instead, which follows the input the shell accepts.
    static let minimumHitTarget = CrestPlatformLayout.minimumHitTarget
    static let sidebarRowHeight = CrestPlatformLayout.sidebarRowHeight
}
