import SwiftUI

enum MobileCompactAddressBarLayout {
    /// The bar's least height: a 48-point capsule, which the command palette
    /// grown out of it matches.
    static let minimumHeight: CGFloat = 48
    static let horizontalPadding: CGFloat = 14
    static let itemSpacing = CrestSpacing.small
    static let pageActionsControlSize = CGSize(width: 30, height: 36)
    static let reloadControlSize = CGSize(width: 30, height: 36)
    static let reloadMenuControlSize = CGSize(width: 22, height: 36)
    static let clearControlSize = CGSize(width: 28, height: 36)
    /// The lock or magnifying glass that leads the field while it edits.
    static let leadingGlyphWidth: CGFloat = 20
    /// The translation menu beside Page Actions, and the gap before it.
    static let translationControlWidth = CrestLayout.minimumHitTarget
    static let translationLeadingGap = CrestSpacing.small
    static let translationSlotWidth = translationControlWidth + translationLeadingGap
}
