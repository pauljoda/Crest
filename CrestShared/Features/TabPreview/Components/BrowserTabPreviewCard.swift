import SwiftUI

// MARK: - Types

/// A picture of a tab's page that Crest already took, with its proportions.
struct BrowserTabPreviewPicture {
    let image: Image
    /// Height over width.
    let aspectRatio: CGFloat
}

/// The card a sidebar tab shows when the pointer rests on it, or that a held
/// tab's menu shows above it: its title, its site and the last picture Crest
/// took of its page. It reads everything live from the tab and the list that
/// draws it, and never loads, wakes or pictures a page itself.
struct BrowserTabPreviewCard: View {
    // MARK: - Static Variables

    /// The tallest a picture is drawn; a taller page shows its top.
    private static let pictureMaximumHeight: CGFloat = 168
    private static let faviconSize: CGFloat = 16

    // MARK: - Variables

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let picture: BrowserTabPreviewPicture?
    /// Whether the card floats on its own surface, as beside the sidebar,
    /// rather than inside the one the system draws around a menu's preview.
    var floats = true

    @Environment(\.browserTabPreviewCardWidth) private var width

    private var address: String? {
        tab.address.map { BrowserAddressPresentation($0.absoluteString).domain }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        // The header sits a container's padding inside the card's inset, as
        // a row's favicon sits inside its surface, so a card with no picture
        // keeps as much room below its title as above it.
        VStack(alignment: .leading, spacing: CrestSpacing.small - BrowserSidebarMetrics.containerPadding) {
            header
                .padding(BrowserSidebarMetrics.containerPadding)
            if let picture {
                pictureView(picture)
            }
        }
        .padding(BrowserTabPreviewSurface.padding)
        .modifier(BrowserTabPreviewCardSurface(floats: floats, width: width))
        // The card repeats what the tab's row already tells VoiceOver.
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.small) {
            TabStateFaviconView(
                tab: tab, favicons: context.favicons, profileID: context.profileID, size: Self.faviconSize
            )
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall / 2) {
                Text(tab.shownTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func pictureView(_ picture: BrowserTabPreviewPicture) -> some View {
        let width = self.width - BrowserTabPreviewSurface.padding * 2
        let height = min(width * picture.aspectRatio, Self.pictureMaximumHeight)
        let shape = RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius())
        return picture.image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

/// A tab card's own floating surface, or, inside the surface the system draws
/// around a menu's preview, the plain ground of a page.
private struct BrowserTabPreviewCardSurface: ViewModifier {
    let floats: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        if floats {
            content.browserTabPreviewSurface()
        } else {
            content
                .frame(width: width, alignment: .leading)
                .background(.background)
        }
    }
}
