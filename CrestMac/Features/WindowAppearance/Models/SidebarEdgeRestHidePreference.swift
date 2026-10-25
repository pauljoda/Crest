import Foundation

/// How long a pointer may rest motionless at the screen edge over a revealed
/// sidebar before the sidebar hides, for a pointer that Universal Control has
/// taken to another Mac. Zero, the default, keeps the sidebar until the
/// pointer moves off it or focus moves away.
/// The delay itself is ``BrowserDeviceAppearanceStore/sidebarEdgeRestHideDelay``.
enum SidebarEdgeRestHidePreference {
    static let range: ClosedRange<Double> = 0...10
    static let defaultValue: Double = 0

    /// A stored value clamped to whole seconds in range, so a stale or
    /// hand-edited default never hides the sidebar at once.
    static func delay(_ stored: Double) -> TimeInterval {
        min(max(stored.rounded(), range.lowerBound), range.upperBound)
    }
}
