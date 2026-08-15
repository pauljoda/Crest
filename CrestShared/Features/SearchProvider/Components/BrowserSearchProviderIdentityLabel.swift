import SwiftUI

struct BrowserSearchProviderIdentityLabel: View {
    let provider: BrowserSearchProvider
    var title: String? = nil
    var iconSize: CGFloat = 20

    var body: some View {
        Label {
            Text(title ?? provider.title)
        } icon: {
            BrowserSearchProviderIcon(provider: provider, size: iconSize)
        }
    }
}

#Preview("Search Provider Labels") {
    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
        ForEach(BrowserSearchProvider.allCases) { provider in
            BrowserSearchProviderIdentityLabel(provider: provider)
        }
    }
    .padding(CrestSpacing.large)
    .frame(width: 240, alignment: .leading)
}
