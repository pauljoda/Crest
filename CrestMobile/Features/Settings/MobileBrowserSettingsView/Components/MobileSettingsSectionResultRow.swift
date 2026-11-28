import SwiftUI

/// A section a Settings search matched, indented under the row of the page
/// it's on. Choosing it opens the page at the section.
struct MobileSettingsSectionResultRow: View {
    /// Lines the section up with the title of the page row above it.
    private static let indent: CGFloat = 44

    let section: BrowserSettingsSection

    var body: some View {
        Text(section.title)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, Self.indent)
            .padding(.vertical, CrestSpacing.extraExtraSmall)
            .contentShape(.rect)
    }
}
