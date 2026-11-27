import Foundation

/// One row of the Settings sidebar: a settings page, a Space's page, or, while
/// searching, a section of either that the search matched.
///
/// The item is the sidebar list's selection and the shown page's identity, so
/// it stays one hashable value. Each case says which row shows it and what
/// choosing it does. A section row is only ever chosen, never shown: choosing
/// it shows its page, opened at the section.
enum BrowserSettingsSidebarItem: Hashable {
    case destination(BrowserSettingsDestination)
    case space(UUID)
    /// A section of a settings page, listed under it while searching.
    case section(BrowserSettingsSection, of: BrowserSettingsDestination)
    /// A section of one Space's page, listed under the Space while searching.
    case spaceSection(BrowserSettingsSection, tab: BrowserSpaceSettingsTab, space: UUID)

    // MARK: - Variables

    /// The row that shows the item. A page without a row selects the row it
    /// lives under.
    var row: BrowserSettingsSidebarItem {
        switch self {
        case .destination(let destination):
            .destination(BrowserPlatformSettingsDestinationCatalog.parent(of: destination) ?? destination)
        case .space, .section, .spaceSection:
            self
        }
    }

    // MARK: - Actions - Selection

    /// The section choosing the item opens its page at: a section row's
    /// own. A page or Space row opens its page as it always does.
    var section: BrowserSettingsSection? {
        switch self {
        case .section(let section, _), .spaceSection(let section, _, _): section
        case .destination, .space: nil
        }
    }

    /// Chooses the item from the sidebar: a page shows in `tabState`; a Space
    /// opens through `openSpace`, on the page given or the one it last
    /// showed.
    @MainActor
    func select(on tabState: BrowserSettingsTabState, openSpace: (UUID, BrowserSpaceSettingsTab?) -> Void) {
        switch self {
        case .destination:
            tabState.navigation.selection = self
        case .section(_, let destination):
            tabState.navigation.selection = .destination(destination)
        case .space(let id):
            // Arranging drags rows; a press that starts a drag isn't a choice.
            guard !tabState.isArrangingSpaces else { return }
            openSpace(id, nil)
        case .spaceSection(_, let tab, let id):
            openSpace(id, tab)
        }
    }
}
