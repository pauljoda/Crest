import SwiftUI

/// What a compact page's bar offers in search mode, the Open Search startup
/// choice: a search field in place of the address that searches for a new
/// tab, and a page menu that opens as a sheet. A window without search mode
/// has none, and its bar shows the address.
struct MobileSearchModeControls {
    /// Puts search up over the shown tab; what is opened from it goes to a
    /// new tab.
    let search: @MainActor () -> Void
    /// The Spaces New Tab's menu offers a new tab in: the window's others
    /// that are not locked.
    let otherSpaces: [SpaceModel]
    /// Moves to a Space and puts search up there, for a new tab in it.
    let searchInSpace: @MainActor (UUID) -> Void
    /// Whether the window browses privately, which New Tab's menu offers to
    /// leave.
    let isPrivateBrowsing: Bool
    let togglePrivateBrowsing: @MainActor () -> Void
    /// Pins or unpins the shown tab, as the tab's own menu does.
    let toggleShownTabPinned: @MainActor () -> Void
    /// Whether the page menu is up. The window keeps it, so search does not
    /// come up by itself under the menu.
    let isPageMenuPresented: Binding<Bool>
}
