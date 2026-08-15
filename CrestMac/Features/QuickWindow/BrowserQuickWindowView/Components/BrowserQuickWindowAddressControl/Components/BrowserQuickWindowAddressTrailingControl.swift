import SwiftUI

struct BrowserQuickWindowAddressTrailingControl: View {
    let page: BrowserPage?
    @Binding var addressText: String
    let isAddressEditing: Bool
    let reloadOrStop: () -> Void

    var body: some View {
        Group {
            if isAddressEditing, !addressText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    addressText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            } else if let page {
                BrowserReloadControl(
                    isLoading: page.isLoading,
                    isDeveloperMode: page.isDeveloperModeEnabled,
                    reloadOrStop: reloadOrStop,
                    reload: { page.performReload(.standard) },
                    reloadFromOrigin: { page.performReload(.fromOrigin) },
                    clearSiteDataAndReload: page.clearSiteDataAndReload
                )
            }
        }
    }
}

#Preview("Quick Window Clear Address") {
    @Previewable @State var addressText = "example.com"
    BrowserQuickWindowAddressTrailingControl(
        page: nil,
        addressText: $addressText,
        isAddressEditing: true,
        reloadOrStop: {}
    )
    .padding()
}
