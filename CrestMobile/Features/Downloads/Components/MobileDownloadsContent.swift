import SwiftUI

struct MobileDownloadsContent: View {
    let space: SpaceModel?
    let downloads: [DownloadState]
    let actions: BrowserUtilityListActions
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            MobileUtilityList(surface: .downloads, space: space, downloads: downloads, actions: actions)
                .navigationTitle("Downloads")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss)
                    }
                }
        }
        .frame(minWidth: 320, minHeight: 300)
        .presentationDetents([.medium, .large])
    }
}
