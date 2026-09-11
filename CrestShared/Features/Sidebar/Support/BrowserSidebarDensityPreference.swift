import SwiftUI

@MainActor
enum BrowserSidebarDensityPreference {
    static let defaults = BrowserFolderAppearancePreference.defaults
    static let scaleKey = "crest.appearance.tabScale"
    static let pinColumnsKey = "crest.appearance.pinColumns"

    static func number(_ key: String, default fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.double(forKey: key)
        return value.isFinite ? value : fallback
    }
}

enum BrowserSidebarDensityPolicy {
    #if os(macOS)
        static let bodySize: CGFloat = 13
        static let usesTouch = false
    #else
        static let bodySize: CGFloat = 17
        static let usesTouch = true
    #endif

    /// The range and step the sidebar's own tab scale honors.
    static let scaleRange: ClosedRange<Double> = 0.7...1.4
    static let scaleStep = 0.05

    static func scale(_ value: Double) -> Double {
        value.isFinite ? min(max(value, scaleRange.lowerBound), scaleRange.upperBound) : 1
    }

    static func rowHeight(base: CGFloat, scale value: Double, touch: Bool) -> CGFloat {
        max(touch ? 44 : 24, base * scale(value))
    }

    static func rowSeparation(scale value: Double, hasBorders: Bool = false) -> Double {
        value < 1 || hasBorders ? 2 : 0
    }

    static func pinHeight(scale value: Double) -> Double {
        max(usesTouch ? 44 : 32, 47 * scale(value))
    }

    static func pinSpacing(scale value: Double) -> Double { max(2, 8 * scale(value)) }

    static func pinMinimumWidth(scale value: Double) -> Double {
        max(usesTouch ? 44 : 24, 36 * scale(value))
    }
}
