import Foundation

extension StartupBehavior {
    // MARK: - Static Variables

    /// The choices, in the order the settings offer them.
    #if os(macOS)
        static let settingsOrder: [StartupBehavior] = [.lastActiveTab, .showStartPage]
    #else
        /// A phone or iPad opens on its tab viewer, which is its Start Page, a
        /// new tab, or search over the tab it last showed.
        static let settingsOrder: [StartupBehavior] = [.showStartPage, .newTab, .search]
    #endif

    // MARK: - Actions - Settings

    /// The choice the settings show for this one: itself where they offer
    /// it, else the offered choice that greets a window the same way, with a
    /// new tab, with search or with neither. A phone's window opens without
    /// a tab, so the last active tab, which only a Mac offers, shows there as
    /// the Start Page it opens on. One no offered choice matches shows as
    /// itself.
    var settingsChoice: StartupBehavior {
        guard !Self.settingsOrder.contains(self) else { return self }
        return Self.settingsOrder.first { $0.opensNewTab == opensNewTab && $0.presentsSearch == presentsSearch }
            ?? self
    }
}
