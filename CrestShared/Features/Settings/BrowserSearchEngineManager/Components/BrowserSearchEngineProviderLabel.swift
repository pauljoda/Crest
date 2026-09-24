import SwiftUI

struct BrowserSearchEngineProviderLabel: View {
    let provider: SearchProvider
    let profileID: UUID
    let isSelected: Bool

    var body: some View {
        HStack {
            BrowserSearchProviderIdentityLabel(provider: provider, profileID: profileID)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}
