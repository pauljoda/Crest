import Foundation

/// How long the pointer rests on the strip along the window's edge before a
/// hidden sidebar shows. The delay itself, in milliseconds, is
/// ``BrowserDeviceAppearanceStore/sidebarRevealDelay``.
enum SidebarRevealDelayPreference {
    // MARK: - Static Variables

    static let range: ClosedRange<Double> = 0...1000
    static let defaultValue = BrowserLookAndFeelDefaults.sidebarRevealDelay

    // MARK: - Actions - Delay

    /// A stored delay in whole steps of ten milliseconds within ``range``, so
    /// a stale or hand-edited default never waits forever or less than nothing.
    static func delay(_ stored: Double) -> Duration {
        let milliseconds = stored.isFinite ? min(max(stored, range.lowerBound), range.upperBound) : defaultValue
        return .milliseconds(Int((milliseconds / 10).rounded()) * 10)
    }
}
