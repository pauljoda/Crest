import Foundation

enum BrowserTabMigrationSource: String, CaseIterable, Identifiable, Sendable {
    case safari
    case chrome
    case firefox
    case arc
    case zen

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .safari: "Safari Session"
        case .chrome: "Chrome or Chromium Session"
        case .firefox: "Firefox Session"
        case .arc: "Arc Sidebar or Session"
        case .zen: "Zen Spaces or Session"
        }
    }

    var importedSpaceName: LocalizedStringResource {
        switch self {
        case .safari: "Imported Safari Tabs"
        case .chrome: "Imported Chrome Tabs"
        case .firefox: "Imported Firefox Tabs"
        case .arc: "Imported Arc Tabs"
        case .zen: "Imported Zen Tabs"
        }
    }

    var symbol: String {
        switch self {
        case .safari: "safari"
        case .chrome: "globe"
        case .firefox: "flame"
        case .arc: "sidebar.left"
        case .zen: "circle.hexagongrid.fill"
        }
    }

    var accent: SpaceAccent {
        switch self {
        case .safari: .teal
        case .chrome: .orange
        case .firefox: .rose
        case .arc: .indigo
        case .zen: .indigo
        }
    }
}
