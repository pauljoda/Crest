import SwiftUI

enum CrestStartPageMarkMetrics {
    /// The grid the mark is drawn on, in points at its full size.
    static let grid: CGFloat = 64
    /// The tile's corner, as a share of its side: 15 points on the grid.
    static let cornerRadiusRatio: CGFloat = 15 / 64
    static let borderOpacity: CGFloat = 0.12
    /// The side at and below which the mark is drawn flat, keylined rather
    /// than shadowed.
    static let flatSide: CGFloat = 32
    /// The keyline's width on the grid; only its outer half shows.
    static let keylineWidth: CGFloat = 2.6
    /// The near-black the paper layers' shadows fall in.
    static let shadow = Color(red: 0.024, green: 0.039, blue: 0.078)
}
