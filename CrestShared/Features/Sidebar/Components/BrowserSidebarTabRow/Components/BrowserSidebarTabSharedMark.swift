import SwiftUI

/// Marks a tab another page shares, with the symbol Site Controls gives
/// Screen Sharing, so the row says it with more than its outline's color.
/// Where the row can act, the mark opens a popover that goes to the tab
/// sharing it or stops the sharing.
struct BrowserSidebarTabSharedMark: View {
    // MARK: - Variables

    /// The tab whose page shares this one, when Crest knows it.
    var sharingTab: TabStateModel? = nil
    var goToSharingTab: (() -> Void)? = nil
    var stopSharing: (() -> Void)? = nil

    @State private var isPresentingActions = false

    var body: some View {
        if let stopSharing {
            Button {
                isPresentingActions = true
            } label: {
                symbol
            }
            .buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: CGSize(
                        width: BrowserSidebarTabSharedMarkMetrics.controlSize,
                        height: BrowserSidebarTabSharedMarkMetrics.controlSize))
            )
            .help(Text("This tab is being shared", comment: "Tooltip on a sidebar tab another page shares."))
            .accessibilityLabel(Text("Shared", comment: "Accessibility label for a sidebar tab another page shares."))
            .popover(isPresented: $isPresentingActions, arrowEdge: .trailing) {
                actions(stopSharing: stopSharing)
            }
        } else {
            symbol
                .help(Text("This tab is being shared", comment: "Tooltip on a sidebar tab another page shares."))
                .accessibilityLabel(
                    Text("Shared", comment: "Accessibility label for a sidebar tab another page shares."))
        }
    }

    // MARK: - Actions - Layout

    private var symbol: some View {
        Image(systemName: SitePermission.screenSharing.symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func actions(stopSharing: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if let sharingTab {
                Text(
                    "Shared to \(sharingTab.shownTitle)",
                    comment: "Shared tab popover; the value is the tab it is shared to."
                )
                .font(.callout)
                .lineLimit(2)
            }
            HStack(spacing: CrestSpacing.small) {
                if let sharingTab, let goToSharingTab {
                    Button {
                        isPresentingActions = false
                        goToSharingTab()
                    } label: {
                        Text("Go to Tab", comment: "Shared tab popover button that shows the tab it is shared to.")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text(sharingTab.shownTitle))
                }
                Button {
                    isPresentingActions = false
                    stopSharing()
                } label: {
                    Text("Stop Sharing", comment: "Stops the tab sharing a tab takes part in.")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(BrowserSidebarTabSharedMarkMetrics.popoverPadding)
        .frame(width: BrowserSidebarTabSharedMarkMetrics.popoverWidth, alignment: .leading)
    }
}

#if DEBUG
    #Preview("Indicator and control") {
        HStack(spacing: 20) {
            BrowserSidebarTabSharedMark()
            BrowserSidebarTabSharedMark(stopSharing: {})
        }
        .padding()
    }
#endif
