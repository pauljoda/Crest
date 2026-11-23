import SwiftUI

/// A setup form section's rows, raised in slate where they lie on setup's
/// paper, and drawn as the platform draws them elsewhere.
struct BrowserSetupRaisedRows: ViewModifier {
    // MARK: - Variables

    @Environment(\.liesOnBrowserSetupPaper) private var liesOnPaper

    // MARK: - Actions - Drawing

    func body(content: Content) -> some View {
        content.listRowBackground(liesOnPaper ? BrowserSetupPaper.raisedFill : nil)
    }
}
