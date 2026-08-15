import CoreGraphics

enum BrowserPeekChromePolicy {
    static let placesControlsAboveCard = true
    static let alignsControlsToTrailingEdge = true
    static let controlHeight: CGFloat = 48
    static let closeControlWidth: CGFloat = 206
    static let openControlWidth: CGFloat = 206
    static let controlSpacing: CGFloat = 10
    static let destinationLeadingInset: CGFloat = 16
    static let destinationControlWidth: CGFloat = 48
    static let destinationContentSpacing = CrestSpacing.small
    static let destinationIconSize: CGFloat = 22
    static let separatorOpacity = 0.16
    static let separatorWidth: CGFloat = 0.5
    static let separatorHeight: CGFloat = 22
    static let openInTitle = "Open In…"
    static let primaryActionOpensSelectedSpace = true
    static let usesSpaceBackgroundTint = true
    static let showsTrailingSpaceMenu = true

    static var controlBarWidth: CGFloat {
        closeControlWidth + controlSpacing + openControlWidth
    }

    static func menuTitle(spaceName: String) -> String {
        spaceName
    }
}
