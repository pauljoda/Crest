import SwiftUI

struct BrowserPeekDestinationPrimaryButton: View {
    // MARK: - Types

    /// Offers its content at most `maximumWidth` and is as wide as the
    /// content answers, so a short title stays short and a long one is cut
    /// at the cap.
    private struct CappedWidth: Layout {
        let maximumWidth: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let content = subviews.first else { return .zero }
            let width = min(proposal.width ?? maximumWidth, maximumWidth)
            return content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(
                at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }

    // MARK: - Static Variables

    private static let contentSpacing = CrestSpacing.small
    private static let title = "Open In…"

    // MARK: - Variables

    let selectedSpace: BrowserSpaceIdentity?
    var style = BrowserPeekControlStyle.actionBar
    let openInSelectedSpace: () -> Void

    /// "Open in" and the Space's name where the style has room for it, cut
    /// short when the name is long, or else "Open In…".
    @ViewBuilder private var title: some View {
        if let width = style.spaceNameWidth, let selectedSpace {
            CappedWidth(maximumWidth: width) {
                Text("Open in \(selectedSpace.name)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(Self.title)
                .lineLimit(1)
        }
    }

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
                title
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
