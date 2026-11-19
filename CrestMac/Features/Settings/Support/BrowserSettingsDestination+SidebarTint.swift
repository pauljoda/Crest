import AppKit
import SwiftUI

extension BrowserSettingsDestination {
    /// The sidebar glyph's tint: the destination's brand color at a
    /// brightness the sidebar reads at.
    var sidebarTint: Color { color.sidebarGlyphColor }
}

extension Color {
    /// The color at a brightness a sidebar glyph reads at: lifted a little in
    /// Dark Mode, and the bright brand colors, such as butter and sky,
    /// deepened in Light Mode so they hold on cream, keeping the hue.
    fileprivate var sidebarGlyphColor: Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let shown = isDark ? max(brightness, 0.8) : min(brightness, 0.72)
                let held = isDark ? saturation : min(1, saturation * 1.12)
                return NSColor(hue: hue, saturation: held, brightness: shown, alpha: 1)
            })
    }
}
