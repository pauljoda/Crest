import SwiftUI

/// The downloads of the page's Space, newest first, and the way to every
/// download.
struct SiteControlsDownloadsPage: View {
    /// How many of the Space's downloads the page lists.
    private static let limit = 6

    let model: SiteControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            let downloads = Array(model.downloads.prefix(Self.limit))
            if !downloads.isEmpty {
                SiteControlsPageSection(
                    title: model.platform.space.map { LocalizedStringResource("In \($0.identity.name)") }
                ) {
                    ForEach(downloads) { download in
                        SiteControlsRowLabel(
                            title: Text(verbatim: download.filename), symbol: download.phase.symbol ?? "doc",
                            subtitle: download.phase.title.map { Text($0) }
                        ) {
                            if download.phase.isTransferring {
                                SiteControlsRowValue(value: "\(Int((download.progress * 100).rounded()))%")
                            }
                        }
                    }
                }
            }
            SiteControlsPageSection {
                SiteControlsRow(
                    title: Text("Show All Downloads"), symbol: "arrow.down.circle",
                    titleTint: CrestBrandTheme.accentText
                ) {
                    model.platform.dismiss()
                    model.platform.run(.showDownloads)
                } trailing: {
                    EmptyView()
                }
                .accessibilityIdentifier("site-control-show-all-downloads")
            }
        }
    }
}
