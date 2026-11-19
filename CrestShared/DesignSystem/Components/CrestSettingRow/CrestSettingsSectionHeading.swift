import SwiftUI

/// A settings section's title, in the platform's section-header place and
/// Crest's rounded heavy type.
struct CrestSettingsSectionHeading: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(CrestTypography.sectionHeading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
