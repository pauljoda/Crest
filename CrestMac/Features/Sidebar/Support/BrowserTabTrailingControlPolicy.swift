import SwiftUI

enum BrowserTabTrailingControlPolicy {
    static let minimumHitTarget = CrestLayout.minimumHitTarget
    static let glyphSize: CGFloat = 12
    static let claimsItsFullHitTarget = true
    static let isSeparatedFromActivationTarget = true
    static let usesSharedHoverSurface = true
    static let preservesSidebarRowHeight = true
    static let size = CGSize(width: minimumHitTarget, height: minimumHitTarget)
}
