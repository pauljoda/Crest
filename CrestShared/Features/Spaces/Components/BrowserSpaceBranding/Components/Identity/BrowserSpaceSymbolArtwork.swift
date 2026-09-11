import SwiftUI

/// A single original-color platform image used anywhere SwiftUI bridges a Space
/// icon into a native control. Without this boundary, menus and pickers can
/// flatten a layered crest into one template symbol or interpret its layers as
/// separate control elements.
struct BrowserSpaceSymbolArtwork: View {
    let space: BrowserSpace
    let size: CGFloat
    let lockSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var renderedArtwork: BrowserSpaceRenderedSymbolArtwork?

    var body: some View {
        Group {
            if let renderedArtwork {
                renderedArtwork.image
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
            } else {
                if let emoji = BrowserIconSymbol.emoji(from: space.symbol) {
                    Text(emoji)
                        .font(.system(size: size * 0.68))
                } else {
                    Image(systemName: space.symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(space.branding.resolvedSymbolColor.color)
                        .padding(size * 0.2)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: identity) {
            guard !Task.isCancelled else { return }
            let currentIdentity = identity
            let content = BrowserSpaceSymbolArtworkContent(
                space: space,
                size: size,
                lockSize: lockSize
            )
            .environment(\.colorScheme, colorScheme)
            let image = BrowserSpaceSymbolArtworkCache.shared.image(for: currentIdentity) {
                BrowserPlatformSpaceSymbolArtworkRenderer.image(
                    for: content,
                    size: size,
                    scale: displayScale,
                    fallbackSystemImage: space.symbol
                )
            }
            guard !Task.isCancelled, currentIdentity == identity else { return }
            renderedArtwork = BrowserSpaceRenderedSymbolArtwork(
                identity: currentIdentity,
                image: image
            )
        }
    }

    private var identity: BrowserSpaceSymbolArtworkIdentity {
        BrowserSpaceSymbolArtworkIdentity(
            branding: space.branding,
            symbol: space.symbol,
            accessPolicy: space.accessPolicy,
            size: size,
            lockSize: lockSize,
            colorScheme: colorScheme,
            displayScale: displayScale
        )
    }
}

/// Native picker and menu labels often request the same crest at the same size.
/// Share those renders, with a fixed limit as sliders generate new appearances.
@MainActor
final class BrowserSpaceSymbolArtworkCache {
    static let shared = BrowserSpaceSymbolArtworkCache()
    private let capacity: Int
    private var entries: [BrowserSpaceRenderedSymbolArtwork] = []

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    func image(for identity: BrowserSpaceSymbolArtworkIdentity, render: () -> Image) -> Image {
        if let index = entries.firstIndex(where: { $0.identity == identity }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.image
        }
        let image = render()
        if entries.count == capacity { entries.removeFirst() }
        entries.append(BrowserSpaceRenderedSymbolArtwork(identity: identity, image: image))
        return image
    }
}
