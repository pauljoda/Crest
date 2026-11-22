import SwiftUI

/// A palette row's icon drawn from its site's: the icon a tab of the Space
/// wears for the site, with the row's own symbol as a badge in its corner, so
/// a history row still reads as history. Until the icon is decoded, or when
/// it can't be, the row wears its symbol alone, `placeholder`.
struct BrowserCommandPaletteSiteIcon<Placeholder: View>: View {
    // MARK: - Types

    /// The icon as decoded, with the fingerprint of the bytes it came from.
    private struct Decoded {
        let identity: BrowserFaviconPayloadIdentity
        let image: Image
    }

    // MARK: - Variables

    let icon: FaviconAssets.Image
    /// The SF Symbol the badge draws.
    let badge: String
    var size: CGFloat = BrowserCommandPaletteMetrics.rowFaviconSize
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var decoded: Decoded?

    /// The icon's scale against a default-density sidebar row's, which the
    /// badge follows so it keeps its proportion to the icon.
    private var scale: CGFloat { size / TabFaviconMetrics.defaultSize }

    var body: some View {
        Group {
            if let decoded, decoded.identity == icon.identity {
                decoded.image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: TabFaviconMetrics.cornerRadius(for: size)))
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) { badgeView }
            } else {
                placeholder()
            }
        }
        .accessibilityHidden(true)
        .task(id: icon.identity) {
            await decode(icon)
        }
    }

    /// The row's symbol on the disc a tab icon's corner badge sits on, hung
    /// off the icon's corner as an engine's mark is. The palette's material
    /// would let the icon show through the disc's usual ground, so the disc
    /// takes the window's opaque one.
    private var badgeView: some View {
        Image(systemName: badge)
            .resizable()
            .fontWeight(.bold)
            .scaledToFit()
            .foregroundStyle(.secondary)
            .modifier(TabFaviconBadgeDisc(scale: scale))
            .backgroundStyle(CrestColor.windowBackground)
            .offset(x: TabFaviconBadge.overhang * scale, y: TabFaviconBadge.overhang * scale)
    }

    // MARK: - Actions - Decoding

    private func decode(_ icon: FaviconAssets.Image) async {
        guard
            let image = await BrowserFaviconImageDecoder.decode(
                icon.data, maximumPixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size)),
            !Task.isCancelled
        else { return }
        decoded = Decoded(
            identity: icon.identity, image: Image(decorative: image, scale: TabFaviconMetrics.renderedImageScale))
    }
}

#if DEBUG
    #Preview("Site icons with the history badge") {
        // An 8-pixel red square, and bytes that decode to nothing, which leave the clock alone.
        let red = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGO4"
                + "pKuLFTEMLQkAd7tLAVUwzrUAAAAASUVORK5CYII=")!
        HStack(spacing: CrestSpacing.medium) {
            ForEach([red, Data()], id: \.self) { data in
                BrowserCommandPaletteSiteIcon(icon: FaviconAssets.Image(data), badge: PaletteRowKind.history.symbol) {
                    Image(systemName: PaletteRowKind.history.symbol).foregroundStyle(.secondary)
                }
                .frame(
                    width: BrowserCommandPaletteMetrics.rowIconContainerSize,
                    height: BrowserCommandPaletteMetrics.rowIconContainerSize)
            }
        }
        .padding()
    }
#endif
