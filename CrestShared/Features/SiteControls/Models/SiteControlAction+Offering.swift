import Foundation

/// Where this device offers Site Controls' actions.
extension SiteControlAction {
    // MARK: - Actions - Offering

    /// Whether the device offers the action: its platform has it, and the
    /// default engine or an engine a page is open on supports what its
    /// command, or the action itself, needs.
    @MainActor
    func isOffered(in state: CoreState) -> Bool {
        platforms.contains(.current) && (command?.isOffered(in: state) ?? true)
            && (requiredCapability.map(state.offers) ?? true)
    }
}

// MARK: - Identifiable

extension SiteControlAction: Identifiable {
    var id: String { name }
}
