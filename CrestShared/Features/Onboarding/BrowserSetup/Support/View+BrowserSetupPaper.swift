import SwiftUI

extension View {
    /// Draws the view as it reads on setup's paper: light on navy, as in the
    /// dark. While a Space's `look` covers the paper instead, the view reads
    /// as it does on that look over `appearance`.
    func browserSetupPaperContent(
        wearing look: SpaceBranding? = nil, over appearance: ColorScheme = BrowserSetupPaper.colorScheme
    ) -> some View {
        environment(\.colorScheme, look?.colorScheme(over: appearance) ?? BrowserSetupPaper.colorScheme)
            .environment(\.liesOnBrowserSetupPaper, look == nil)
    }

    /// Raises a setup form's rows on setup's paper, where they lie on it,
    /// and leaves them as the platform draws them elsewhere.
    func browserSetupRaisedRows() -> some View {
        modifier(BrowserSetupRaisedRows())
    }
}
