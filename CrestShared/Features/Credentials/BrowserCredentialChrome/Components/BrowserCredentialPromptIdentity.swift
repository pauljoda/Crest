import SwiftUI

/// The mark a fill prompt opens with: the site's own icon where the page has
/// one, a saved login's site icon where a row names one, and the Space's key
/// otherwise.
///
/// The icon is the page's, so it is only shown for a request the page can speak
/// for. A sign-in embedded from somewhere else is named by its own origin on the
/// line beneath, and putting the host page's mark beside that name would say the
/// opposite of what the cross-origin notice says.
struct BrowserCredentialPromptIdentity: View {
    let kind: BrowserCredentialPromptHeaderKind
    let iconData: Data?
    let showsSiteIcon: Bool
    /// The saved login's sites, whose own icon stands in when the page has
    /// none.
    var fallbackOrigins: [CredentialOrigin] = []
    let tint: Color

    @State private var icon = BrowserCredentialSiteIcon()

    var body: some View {
        mark
            .frame(
                width: BrowserCredentialPromptMetrics.headerIdentitySize,
                height: BrowserCredentialPromptMetrics.headerIdentitySize
            )
            .background(
                tint.opacity(
                    BrowserCredentialPromptMetrics.headerIdentityTintOpacity
                ),
                in: .rect(
                    cornerRadius: BrowserCredentialPromptMetrics
                        .headerIdentityCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
            .task(id: requestKey) {
                await loadIcon()
            }
    }

    @ViewBuilder
    private var mark: some View {
        if let image = icon.image(for: requestKey) {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: BrowserCredentialPromptMetrics.headerIdentityIconSize,
                    height: BrowserCredentialPromptMetrics.headerIdentityIconSize
                )
                .clipShape(.rect(cornerRadius: CrestRadius.compact / 2))
        } else {
            Image(systemName: kind.symbol)
                .font(
                    .system(
                        size: BrowserCredentialPromptMetrics
                            .headerIdentitySymbolSize,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
        }
    }

    private var requestedIconData: Data? {
        showsSiteIcon ? iconData : nil
    }

    /// What the mark shows an icon for: the page's bytes, or the saved
    /// login's site when the page has none.
    private var requestKey: AnyHashable? {
        requestedIconData.map(AnyHashable.init) ?? (fallbackOrigins.isEmpty ? nil : AnyHashable(fallbackOrigins))
    }

    private func loadIcon() async {
        let requested = requestKey
        var data = requestedIconData
        if data == nil, !fallbackOrigins.isEmpty {
            data = await BrowserSiteIconStore.shared.icon(forFirstOf: fallbackOrigins)
        }
        guard let data else {
            icon.publish(nil, for: nil)
            return
        }
        let decoded = await BrowserFaviconImageDecoder.decode(
            data,
            maximumPixelSize: BrowserCredentialSiteIcon.maximumPixelSize
        )
        guard !Task.isCancelled, let decoded else { return }
        icon.publish(
            Image(decorative: decoded, scale: BrowserCredentialSiteIcon.scale),
            for: requested
        )
    }
}

/// The last site icon a prompt decoded, and what it was decoded for.
///
/// The bytes are kept beside the image for the same reason a favicon render
/// state keeps its request identity: a decode that lands after the page has
/// moved on is a picture of the wrong site.
@MainActor
struct BrowserCredentialSiteIcon {
    /// Enough pixels for a crisp mark on a 2x display and no more.
    static let maximumPixelSize = 64
    static let scale: CGFloat = 2

    private var request: AnyHashable?
    private var decoded: Image?

    func image(for request: AnyHashable?) -> Image? {
        guard let request, request == self.request else { return nil }
        return decoded
    }

    mutating func publish(_ image: Image?, for request: AnyHashable?) {
        self.request = request
        decoded = image
    }
}
