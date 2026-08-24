import SwiftUI

struct BrowserSearchProviderIcon: View {
    let provider: BrowserSearchProvider
    var profileID: UUID? = nil
    var size: CGFloat = 20

    @State private var customIcon: Image?

    var body: some View {
        Group {
            if let logoAssetName = provider.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else if let customIcon {
                customIcon
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: size * 0.18))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: size * 0.65, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: taskIdentity) {
            await loadCustomIcon()
        }
    }

    private var taskIdentity: String {
        "\(provider.id.rawValue)-\(profileID?.uuidString ?? "none")"
    }

    private func loadCustomIcon() async {
        guard
            provider.builtIn == nil,
            let profileID,
            let pageURL = provider.iconPageURL
        else {
            customIcon = nil
            return
        }
        guard
            let data = await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            ),
            let image = await BrowserFaviconImageDecoder.decode(
                data,
                maximumPixelSize: 64
            ),
            !Task.isCancelled
        else { return }
        customIcon = Image(decorative: image, scale: 2)
    }
}
