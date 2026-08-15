import SwiftUI

struct MobileBrowserPeekSourceTransform: Equatable {
    let anchor: UnitPoint
    let scaleX: CGFloat
    let scaleY: CGFloat

    static let identity = MobileBrowserPeekSourceTransform(
        anchor: .center,
        scaleX: 1,
        scaleY: 1
    )
}
