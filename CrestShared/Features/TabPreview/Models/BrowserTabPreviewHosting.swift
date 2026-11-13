import SwiftUI

/// How a shell's windows bring up a sidebar row's preview card, which names
/// the Appearance section that turns the cards off.
@MainActor
struct BrowserTabPreviewHosting {
    // MARK: - Static Variables

    /// A pointer resting on a row, as on the Mac.
    static let hover = BrowserTabPreviewHosting(settingsTitle: "Preview hover")
    /// A pointer resting on a row, or a finger holding it, as on an iPhone or
    /// iPad.
    static let hoverAndHold = BrowserTabPreviewHosting(settingsTitle: "Previews")

    // MARK: - Variables

    /// The Appearance section's name.
    let settingsTitle: LocalizedStringKey
}

extension EnvironmentValues {
    /// How the app's windows bring up a sidebar row's preview card, so its
    /// settings offer to turn the cards off, or nil where they draw none.
    @Entry var browserTabPreviewHosting: BrowserTabPreviewHosting? = nil
}
