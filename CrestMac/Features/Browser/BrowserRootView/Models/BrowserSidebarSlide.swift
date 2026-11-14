import SwiftUI

/// The sidebar's slides at the length the person chose in Appearance.
///
/// Every sidebar motion keeps its own curve and its length beside the others:
/// the choice is the length of the slide out over the page, and every other
/// slide — retreating, hiding, docking — stretches or shortens by the same
/// factor. A length of zero puts the sidebar in place at once, as Reduce
/// Motion does. The length itself, in milliseconds, is
/// ``BrowserDeviceAppearanceStore/sidebarSlideDuration``.
struct BrowserSidebarSlide: Equatable, Sendable {
    // MARK: - Static Variables

    /// The lengths the slide out over the page can take, in milliseconds.
    static let range: ClosedRange<Double> = 0...480
    static let defaultValue = BrowserLookAndFeelDefaults.sidebarSlideDuration

    /// The slide the person chose.
    @MainActor static var chosen: BrowserSidebarSlide {
        BrowserSidebarSlide(milliseconds: BrowserDeviceAppearanceStore.shared.sidebarSlideDuration)
    }

    // MARK: - Variables

    /// How each slide's length compares with its standard one; zero snaps.
    let scale: Double

    /// Whether the sidebar goes into place at once.
    var snaps: Bool { scale == 0 }

    // MARK: - Initializers

    /// The slide that takes `milliseconds`, in whole steps of ten within
    /// ``range``, to come out over the page. A stale or hand-edited length
    /// never stalls the sidebar or runs it backwards.
    init(milliseconds: Double) {
        let length =
            milliseconds.isFinite
            ? min(max(milliseconds, Self.range.lowerBound), Self.range.upperBound) : Self.defaultValue
        scale = (length / 10).rounded() * 10 / Self.defaultValue
    }

    // MARK: - Actions - Motion

    /// `motion`, one of the sidebar's own, at this slide's length, or nil
    /// where the sidebar snaps.
    func animation(_ motion: Animation) -> Animation? {
        snaps ? nil : motion.speed(1 / scale)
    }

    /// How long a phase that waits out `length` of standard motion waits at
    /// this slide's length.
    func delay(_ length: Duration) -> Duration {
        length * scale
    }
}
