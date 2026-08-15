import Foundation

enum BrowserWindowTransparencyPolicy {
    static let defaultEnabled = true
    static let defaultStrength = 0.18
    static let strengthRange = 0.0...0.45

    static var defaultPreference: BrowserWindowTransparencyPreference {
        BrowserWindowTransparencyPreference(
            isEnabled: defaultEnabled,
            strength: defaultStrength
        )
    }

    static func normalizedStrength(_ strength: Double) -> Double {
        min(max(strength, strengthRange.lowerBound), strengthRange.upperBound)
    }

    static func baseLayerOpacity(
        isEnabled: Bool,
        strength: Double,
        isWindowFocused: Bool
    ) -> Double {
        guard isEnabled, isWindowFocused else { return 1 }
        return 1 - normalizedStrength(strength)
    }

    static func backdropMaterialOpacity(
        isEnabled: Bool,
        isWindowFocused: Bool
    ) -> Double {
        1
    }
}
