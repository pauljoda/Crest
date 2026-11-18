import SwiftUI

/// Where setup's edits to one Space go, as bindings that read the Space as
/// setup holds it now: the manual setup, for a Space the browser has or setup
/// makes, or, on a Mac, the review of a Space an import brings in new.
@MainActor
struct BrowserSetupSpaceEditor {
    // MARK: - Variables

    let name: Binding<String>
    let symbol: Binding<String>
    let branding: Binding<SpaceBranding>

    // MARK: - Initializers

    init(name: Binding<String>, symbol: Binding<String>, branding: Binding<SpaceBranding>) {
        self.name = name
        self.symbol = symbol
        self.branding = branding
    }

    /// The editor for `spaceID` in the manual setup, or nil when it holds no
    /// Space of that identity.
    init?(setup: BrowserManualSetupModel, spaceID: UUID) {
        guard setup.space(spaceID) != nil else { return nil }
        self.init(
            name: setup.nameBinding(for: spaceID), symbol: setup.symbolBinding(for: spaceID),
            branding: setup.brandingBinding(for: spaceID))
    }
}
