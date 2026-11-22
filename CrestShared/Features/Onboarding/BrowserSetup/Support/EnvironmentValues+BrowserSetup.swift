import SwiftUI

extension EnvironmentValues {
    /// Whether setup's pages show their own names over their first section,
    /// as they do beside the Mac's preview. In a navigation stack that names
    /// each page in its bar, they show none.
    @Entry var browserSetupShowsHeadings = true
}
