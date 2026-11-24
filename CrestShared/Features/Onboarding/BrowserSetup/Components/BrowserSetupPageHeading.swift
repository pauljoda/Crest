import SwiftUI

/// A setup page's name over its first section, where the page shows its own
/// name. In a navigation stack that names each page in its bar, it shows
/// nothing.
struct BrowserSetupPageHeading: View {
    // MARK: - Variables

    let title: Text
    @Environment(\.browserSetupShowsHeadings) private var showsHeadings

    // MARK: - Initializers

    init(_ title: LocalizedStringResource) {
        self.title = Text(title)
    }

    init(verbatim title: String) {
        self.title = Text(verbatim: title)
    }

    // MARK: - Actions - Drawing

    var body: some View {
        if showsHeadings {
            title
                .font(CrestTypography.display(22, relativeTo: .title2))
                .foregroundStyle(Color.primary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
