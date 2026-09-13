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
    static let scaleRange: ClosedRange<Double> = 0.7...1.4
    static let scaleStep = 0.05
    private static let pointerBodySize: CGFloat = 13
    private static let touchBodySize: CGFloat = 17
    private static let minimumTouchTarget: CGFloat = 44
    private static let minimumPointerTarget: CGFloat = 24
    private static let minimumPointerPinHeight: CGFloat = 32
    private static let basePinHeight: CGFloat = 47
    private static let basePinWidth: CGFloat = 36
    private static let basePinSpacing: CGFloat = 8
    private static let minimumSpacing: CGFloat = 2

    static func bodySize(touch: Bool) -> CGFloat {
        touch ? touchBodySize : pointerBodySize
    }

    static func scale(_ value: Double) -> Double {
        value.isFinite ? min(max(value, scaleRange.lowerBound), scaleRange.upperBound) : 1
    }

    static func rowHeight(base: CGFloat, scale value: Double, touch: Bool) -> CGFloat {
        max(touch ? minimumTouchTarget : minimumPointerTarget, base * scale(value))
    }

    static func rowSeparation(scale value: Double, hasBorders: Bool = false) -> Double {
        value < 1 || hasBorders ? minimumSpacing : 0
    }

    static func pinHeight(scale value: Double, touch: Bool) -> Double {
        max(touch ? minimumTouchTarget : minimumPointerPinHeight, basePinHeight * scale(value))
    }

    static func pinSpacing(scale value: Double) -> Double { max(minimumSpacing, basePinSpacing * scale(value)) }

    static func pinMinimumWidth(scale value: Double, touch: Bool) -> Double {
        max(touch ? minimumTouchTarget : minimumPointerTarget, basePinWidth * scale(value))
    }
}
