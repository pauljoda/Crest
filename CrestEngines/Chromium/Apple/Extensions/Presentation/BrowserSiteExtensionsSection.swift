import SwiftUI

/// The page's extension tiles in Site Controls: one row, so the root keeps
/// its height. The last tile opens the Extensions page when more extensions
/// act on the page than the row holds, and a Chrome Web Store page offers to
/// install its extension there.
struct BrowserSiteExtensionsSection: View {
    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: (BrowserExtensionActionPresentation) -> Void
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }
    /// Installs the extension a Chrome Web Store page shows, or nil elsewhere.
    var install: (() -> Void)?
    let openPage: () -> Void

    var body: some View {
        let columns = BrowserSiteControlMetrics.extensionColumnCount
        let extra = (install == nil ? 0 : 1)
        let overflows = actions.count + extra > columns
        let shown = Array(actions.prefix(overflows ? columns - 1 - extra : columns))
        if actions.isEmpty && install == nil {
            Label("No extension actions for this page", systemImage: "puzzlepiece.extension")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .frame(height: BrowserSiteControlMetrics.extensionActionHeight)
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: BrowserSiteControlMetrics.extensionGridSpacing),
                    count: columns),
                spacing: BrowserSiteControlMetrics.extensionGridSpacing
            ) {
                ForEach(shown) { action in
                    BrowserSiteExtensionActionButton(
                        action: action,
                        perform: { perform(action, $0) },
                        togglePinned: { togglePinned(action) },
                        presentMenu: { presentMenu(action, $0) }
                    )
                }
                if let install {
                    tile("Install Extension…", systemImage: "plus.app", action: install)
                        .accessibilityIdentifier("site-control-install-extension")
                }
                if overflows {
                    tile("All Extensions", systemImage: "ellipsis", action: openPage)
                        .overlay(alignment: .topTrailing) {
                            Text(verbatim: "+\(actions.count - shown.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(4)
                        }
                }
            }
        }
    }

    private func tile(_ title: LocalizedStringResource, systemImage: String, action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: BrowserSiteControlMetrics.extensionGlyphSize - 3, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: BrowserSiteControlMetrics.extensionActionHeight)
                .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
        )
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}
