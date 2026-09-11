import Foundation

enum BrowserSpaceForegroundTone: Equatable, Sendable {
    case light
    case dark
}

enum BrowserSpaceTextColorMode: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case light
    case dark

    var foregroundTone: BrowserSpaceForegroundTone? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum BrowserSpaceIconStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case simpleSymbol
    case layeredCrest
}

enum BrowserSpaceThemeMode: String, Codable, CaseIterable, Equatable, Sendable {
    case banner
    case gradient
}

enum SpaceAccent: String, Codable, CaseIterable, Equatable, Sendable {
    case indigo
    case orange
    case teal
    case rose
}

enum BrowserSpaceBrandColorRole: Int, CaseIterable, Equatable, Identifiable, Sendable {
    case background
    case primary
    case secondary

    var id: Int { rawValue }
}

enum BrowserSpaceBannerPattern: String, Codable, CaseIterable, Equatable, Sendable {
    case solid
    case split
    case bands
    case diagonal
    case chevron
    case quartered
    case stripes
    case checkered
    case lozenges

    var introducedInRenderingVersion: Int {
        switch self {
        case .stripes, .checkered, .lozenges: BrowserSpaceBranding.customizationRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}
