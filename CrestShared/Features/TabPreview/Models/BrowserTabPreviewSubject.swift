import Foundation

/// What a preview card is for: a tab, or a folder and the tabs it holds.
enum BrowserTabPreviewSubject {
    case tab(TabStateModel)
    case folder(FolderStateModel)

    // MARK: - Variables

    /// The tab or folder, as the sidebar's selection names it.
    var item: BrowserSelectionItemID {
        switch self {
        case .tab(let tab): .tab(tab.id)
        case .folder(let folder): .folder(folder.id)
        }
    }

    /// Whether the person keeps this kind of preview on, in Appearance.
    @MainActor var isTurnedOn: Bool {
        switch self {
        case .tab: BrowserDeviceAppearanceStore.shared.previewsTabsOnHover
        case .folder: BrowserDeviceAppearanceStore.shared.previewsFoldersOnHover
        }
    }

    /// Whether the card takes the keyboard while it shows, for its search.
    var capturesKeys: Bool {
        if case .folder = self { return true }
        return false
    }
}
