import SwiftUI

struct BrowserPeekDestinationPrimaryButton: View {
    // MARK: - Static Variables

    private static let contentSpacing = CrestSpacing.small
    private static let title = "Open In…"

    // MARK: - Variables

    let selectedSpace: BrowserSpaceIdentity?
    var style = BrowserPeekControlStyle.actionBar
    let openInSelectedSpace: () -> Void

    var body: some View {
        Button(action: openInSelectedSpace) {
            HStack(spacing: Self.contentSpacing) {
                if let selectedSpace {
                    BrowserSpaceIdentityIcon(
                        identity: selectedSpace,
                        size: style.iconSize
                    )
                } else {
                    Image(systemName: "square.grid.2x2")
                }
                Text(Self.title)
                    .lineLimit(1)
            }
            .frame(maxWidth: style == .actionBar ? .infinity : nil)
            .padding(.leading, style.leadingInset)
            .padding(.trailing, style == .actionBar ? 0 : CrestSpacing.small)
            .frame(height: style.height)
            .contentShape(.rect)
        }
        .keyboardShortcut("o", modifiers: .command)
        .accessibilityLabel(Text(Self.title))
        .accessibilityValue(Text(selectedSpace?.name ?? "Space"))
        .accessibilityIdentifier("peek-open-selected-space")
        .help("Open in \(selectedSpace?.name ?? "Space") (⌘O)")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserPeekDestinationPrimaryButton(
            selectedSpace: BrowserSpaceBrandingPreviewFixture.simpleSpace.identity, openInSelectedSpace: {}
        ).padding()
    }
#endif
