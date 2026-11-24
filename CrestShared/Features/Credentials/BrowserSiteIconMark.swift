import SwiftUI

// MARK: - Types

/// What a site icon mark's image was made for, so a late load never shows
/// another site's icon.
private struct BrowserSiteIconMarkKey: Hashable {
    let origins: [CredentialOrigin]
    let knownIconData: Data?
}

/// A saved login's site icon: the one the page already gave Crest, or the
/// own icon of the first of the login's sites that has one, fetched once,
/// and `symbol` until there is one.
struct BrowserSiteIconMark: View {
    // MARK: - Static Variables

    /// Enough pixels for a crisp mark on a 2x display and no more.
    private static let maximumPixelSize = 64

    // MARK: - Variables

    let origins: [CredentialOrigin]
    var knownIconData: Data? = nil
    let symbol: String
    let tint: Color
    let size: CGFloat

    @State private var shown: (key: BrowserSiteIconMarkKey, image: Image)?

    private var key: BrowserSiteIconMarkKey {
        BrowserSiteIconMarkKey(origins: origins, knownIconData: knownIconData)
    }

    var body: some View {
        Group {
            if let shown, shown.key == key {
                shown.image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: size / 5, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: key) { await load() }
    }

    // MARK: - Actions

    private func load() async {
        let requested = key
        let data: Data?
        if let knownIconData {
            data = knownIconData
        } else {
            data = await BrowserSiteIconStore.shared.icon(forFirstOf: origins)
        }
        guard !Task.isCancelled, let data,
            let decoded = await BrowserFaviconImageDecoder.decode(data, maximumPixelSize: Self.maximumPixelSize),
            !Task.isCancelled
        else { return }
        shown = (requested, Image(decorative: decoded, scale: 2))
    }
}
