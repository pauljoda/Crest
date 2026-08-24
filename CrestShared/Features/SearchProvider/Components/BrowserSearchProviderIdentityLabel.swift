import SwiftUI

struct BrowserSearchProviderIdentityLabel: View {
    let provider: BrowserSearchProvider
    var profileID: UUID? = nil
    var title: String? = nil
    var iconSize: CGFloat = 20

    var body: some View {
        Label {
            Text(title ?? provider.title)
        } icon: {
            BrowserSearchProviderIcon(
                provider: provider,
                profileID: profileID,
                size: iconSize
            )
        }
    }
}
