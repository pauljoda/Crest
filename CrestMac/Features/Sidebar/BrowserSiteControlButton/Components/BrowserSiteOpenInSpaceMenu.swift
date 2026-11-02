import SwiftUI

/// Reopens the page's address in a Quick Window in another Space's session,
/// for the same site under another account. Shown while the window has
/// another Space the page can open in.
struct BrowserSiteOpenInSpaceMenu: View {
    let page: BrowserPage
    let dismiss: () -> Void

    var body: some View {
        let groups = page.otherSpaceGroups
        if let url = page.live.documentURL, ExternalWebLink.accepts(url), !groups.isEmpty {
            Menu {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { space in
                        Button {
                            dismiss()
                            page.openInQuickWindow(url, in: space)
                        } label: {
                            BrowserSpaceIdentityLabel(space: space)
                        }
                    }
                }
            } label: {
                Label("Open This Page in", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: BrowserSiteControlMetrics.quickActionHeight)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(
                CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
            )
            .accessibilityIdentifier("site-control-open-in-space")
        }
    }
}
