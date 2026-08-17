import SwiftUI

/// Gives a chrome-owning view one spelling for its explicit chrome animations.
/// Conformers expose the environment's Reduce Motion flag and inherit a
/// `chromeAnimation(_:)` that routes every transaction through
/// `BrowserVisualAccessibilityPolicy`.
@MainActor
protocol BrowserChromeAnimating {
    var reduceMotion: Bool { get }
}

extension BrowserChromeAnimating {
    func chromeAnimation(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}
