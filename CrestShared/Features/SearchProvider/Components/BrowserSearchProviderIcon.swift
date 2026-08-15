import SwiftUI

struct BrowserSearchProviderIcon: View {
    let provider: BrowserSearchProvider
    var size: CGFloat = 20

    var body: some View {
        Image(provider.logoAssetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Search Provider Icons") {
    HStack(spacing: CrestSpacing.large) {
        ForEach(BrowserSearchProvider.allCases) { provider in
            BrowserSearchProviderIcon(provider: provider, size: 28)
        }
    }
    .padding(CrestSpacing.large)
}
