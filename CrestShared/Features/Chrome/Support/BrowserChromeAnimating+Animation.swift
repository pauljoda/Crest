import SwiftUI

extension BrowserChromeAnimating {
    func chromeAnimation(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}
