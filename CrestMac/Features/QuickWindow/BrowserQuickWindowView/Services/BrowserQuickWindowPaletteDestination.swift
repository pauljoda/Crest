import Foundation

/// Where a Quick Window's palette opens what the person picks: an address or
/// a search in the Quick Window's own page, and a tab in the browser window
/// its Space's tabs show in.
@MainActor
struct BrowserQuickWindowPaletteDestination: BrowserPaletteDestination {
    // MARK: - Variables

    let model: BrowserQuickWindowModel
    let source: BrowserSpaceRuntimeAssignment
    /// Whether the Quick Window is in front, which its page loads as.
    let isActive: Bool
    /// Shows a tab of the Space in its browser window, answering whether it
    /// did.
    let showTab: (BrowserTabRuntimeAssignment) -> Bool

    /// The Quick Window's page is none of the window's tabs: its palette
    /// speaks for the Quick Window's Space.
    var paletteSpaceID: UUID? { source.spaceID }

    var isAvailable: Bool { model.selectedAssignment == source && model.spaceModel != nil }

    // MARK: - Initializers

    init(
        model: BrowserQuickWindowModel, isActive: Bool,
        showTab: @escaping (BrowserTabRuntimeAssignment) -> Bool
    ) {
        self.model = model
        source = model.selectedAssignment
        self.isActive = isActive
        self.showTab = showTab
    }

    // MARK: - Actions - Opening

    func selectTab(_ target: BrowserTabRuntimeAssignment) -> Bool {
        guard isAvailable, target.spaceID == source.spaceID, target.profileID == source.profileID else {
            return false
        }
        return showTab(target)
    }

    func openURL(_ url: URL) -> Bool {
        guard isAvailable else { return false }
        return model.open(url, isActive: isActive)
    }
}
