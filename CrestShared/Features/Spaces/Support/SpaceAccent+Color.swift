import SwiftUI

extension SpaceAccent {
    var title: String {
        switch self {
        case .indigo: "Indigo"
        case .orange: "Orange"
        case .teal: "Teal"
        case .rose: "Rose"
        }
    }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .orange: .orange
        case .teal: .teal
        case .rose: .pink
        }
    }

    var secondaryColor: Color {
        switch self {
        case .indigo: .cyan
        case .orange: .pink
        case .teal: .blue
        case .rose: .purple
        }
    }

    func primaryAtmosphereOpacity(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Double {
        let base = colorScheme == .dark ? 0.20 : 0.12
        return contrast == .increased ? base + 0.02 : base
    }

    func secondaryAtmosphereOpacity(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Double {
        let base = colorScheme == .dark ? 0.08 : 0.045
        return contrast == .increased ? base + 0.015 : base
    }
}
