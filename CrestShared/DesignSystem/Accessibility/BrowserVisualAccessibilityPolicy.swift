import SwiftUI

/// Forwarders kept only for call sites other batches own (CrestMobile, the
/// sidebar, tabs, chrome, split view and transient browsing). Each rule now
/// lives on the value it adjusts: `Animation.unlessReducingMotion(_:)`,
/// `CGFloat.unlessReducingMotion(_:)`, `Double.scrimOpacity(reduceTransparency:)`
/// and `Color.readableForeground(colorScheme:)`. Delete this file once those
/// call sites use them directly; the tab close glyph is plain `.primary`.
enum BrowserVisualAccessibilityPolicy {
    static var tabCloseForeground: Color { .primary }

    static func scrimOpacity(_ opacity: Double, reduceTransparency: Bool) -> Double {
        opacity.scrimOpacity(reduceTransparency: reduceTransparency)
    }

    static func spatialScale(_ scale: CGFloat, reduceMotion: Bool) -> CGFloat {
        scale.unlessReducingMotion(reduceMotion)
    }

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }

    static func readableForeground(over background: Color, colorScheme: ColorScheme) -> Color {
        background.readableForeground(colorScheme: colorScheme)
    }
}
