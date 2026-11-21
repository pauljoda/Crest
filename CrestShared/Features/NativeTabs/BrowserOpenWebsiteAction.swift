import SwiftUI

/// Opens a website from Crest's own content, such as Settings, in a new tab of
/// the Space it shows in, which the window then shows.
struct BrowserOpenWebsiteAction {
    // MARK: - Variables

    private let open: @MainActor (URL) -> Void

    // MARK: - Initializers

    init(_ open: @escaping @MainActor (URL) -> Void) {
        self.open = open
    }

    // MARK: - Actions

    @MainActor func callAsFunction(_ url: URL) { open(url) }
}

extension EnvironmentValues {
    /// Opens a website in a new tab from Crest's own content. Nil where the
    /// content has no window to open it in.
    @Entry var browserOpenWebsite: BrowserOpenWebsiteAction? = nil
}
