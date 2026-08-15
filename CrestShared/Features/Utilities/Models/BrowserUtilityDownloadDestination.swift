import Foundation

enum BrowserUtilityDownloadDestination: CaseIterable, Hashable, Identifiable {
    case revealInFinder
    case share
    case files

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .revealInFinder: "Show in Finder"
        case .share: "Share…"
        case .files: "Save to Files…"
        }
    }

    var systemImage: String {
        switch self {
        case .revealInFinder: "magnifyingglass"
        case .share: "square.and.arrow.up"
        case .files: "folder.badge.plus"
        }
    }
}
