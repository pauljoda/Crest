import Foundation

/// How fast a Peek grows out of its link and goes back into it, at the
/// length the person chose in Settings.
///
/// The length is that of the spring a card grows on, in milliseconds,
/// ``BrowserDeviceAppearanceStore/peekOpenDuration``; a card comes to rest,
/// and one going back into its link fades, in step with it. A length of
/// zero puts the card in place at once, as Reduce Motion does.
struct BrowserPeekPace: Equatable, Sendable {
    // MARK: - Static Variables

    /// The lengths a Peek's growth can take, in milliseconds.
    static let range: ClosedRange<Double> = 0...800
    static let defaultValue = BrowserLookAndFeelDefaults.peekOpenDuration
    /// How long a released card's spring runs before it is at rest, against
    /// the spring's own length.
    private static let settlingFactor = 2.0
    /// How long a card going back into its link takes to fade, against the
    /// spring's length.
    private static let returnFadeFactor = 0.92

    /// The pace the person chose.
    @MainActor static var chosen: BrowserPeekPace {
        BrowserPeekPace(milliseconds: BrowserDeviceAppearanceStore.shared.peekOpenDuration)
    }

    // MARK: - Variables

    /// The length of the spring a card grows on, in seconds; zero snaps.
    let springDuration: TimeInterval

    /// Whether a card goes into place at once.
    var snaps: Bool { springDuration == 0 }

    /// How long a released card takes to come to rest.
    var settlingDuration: TimeInterval { springDuration * Self.settlingFactor }

    /// How long a card going back into its link takes to fade away.
    var returnFadeDuration: TimeInterval { springDuration * Self.returnFadeFactor }

    // MARK: - Initializers

    /// The pace whose spring takes `milliseconds`, in whole steps of ten
    /// within ``range``. A stale or hand-edited length never stalls a card.
    init(milliseconds: Double) {
        let length =
            milliseconds.isFinite
            ? min(max(milliseconds, Self.range.lowerBound), Self.range.upperBound) : Self.defaultValue
        springDuration = (length / 10).rounded() * 10 / 1000
    }
}
