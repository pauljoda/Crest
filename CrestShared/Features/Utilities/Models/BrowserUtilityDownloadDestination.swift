import Foundation

enum BrowserUtilityDownloadDestination: CaseIterable, Hashable, Identifiable {
    case open
    case revealInFinder
    case share
    case files

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .revealInFinder: "Show in Finder"
        case .share: "Share…"
        case .files: "Save to Files…"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.up.forward.square"
        case .revealInFinder: "magnifyingglass"
        case .share: "square.and.arrow.up"
        case .files: "folder.badge.plus"
        }
    }
}

enum BrowserUtilityDownloadPrimaryActionPolicy {
    static func destination(
        for state: BrowserDownloadItemState,
        availableDestinations: [BrowserUtilityDownloadDestination]
    ) -> BrowserUtilityDownloadDestination? {
        guard state == .finished,
            availableDestinations.contains(.revealInFinder)
        else { return nil }
        return .revealInFinder
    }
}
