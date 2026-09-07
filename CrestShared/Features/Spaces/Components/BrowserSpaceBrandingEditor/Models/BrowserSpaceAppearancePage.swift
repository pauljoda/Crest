import SwiftUI

/// A single visual decision in the Space editor. Navigation never changes branding.
enum BrowserSpaceAppearancePage: CaseIterable, Identifiable, Sendable {
    case presets, customize, icon, crest, pattern, shape, emblem, border, layout, division, band, palette, background,
        finish

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .crest: "Crest shape and emblem"
        case .pattern: "Crest pattern"
        case .presets: "Choose an appearance"
        case .customize: "Customize your Space"
        case .icon: "Choose an icon"
        case .shape: "Choose a shape"
        case .emblem: "Choose an emblem"
        case .border: "Frame your crest"
        case .layout: "Arrange your emblems"
        case .division: "Divide the field"
        case .band: "Add a band"
        case .palette: "Choose colors"
        case .background: "Sidebar background"
        case .finish: "Adjust the finish"
        }
    }

    var shortTitle: LocalizedStringKey {
        switch self {
        case .crest: "Crest"
        case .pattern: "Pattern"
        case .shape: "Shape"
        case .emblem: "Emblem"
        case .border: "Border"
        case .palette: "Colors"
        case .background: "Background"
        case .layout: "Arrangement"
        case .division: "Field"
        case .band: "Band"
        case .finish: "Finish"
        default: title
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .crest: "Choose a shape, emblem, or border to edit."
        case .pattern: "Arrange the emblems and the colors behind them."
        case .presets: "Choose a preset, then customize its appearance if needed."
        case .customize: "Changes appear in the sidebar preview."
        case .icon: "Use a system symbol or emoji."
        case .shape: "Choose the outline of your crest."
        case .emblem: "Choose the symbol inside your crest."
        case .border: "Choose the border around your crest."
        case .layout: "One emblem, a pair, or a trio."
        case .division: "Split the colors behind your emblem."
        case .band: "Add a stripe or a crossing to the field."
        case .palette: "Choose a palette or edit individual colors."
        case .background: "This is how your colors fill the sidebar."
        case .finish: "Adjust contrast and color intensity."
        }
    }

    static let details: [Self] = [.crest, .pattern, .palette, .background]
}
