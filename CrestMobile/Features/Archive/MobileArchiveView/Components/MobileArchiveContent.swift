import SwiftUI

struct MobileArchiveContent: View {
    let space: BrowserSpace?
    let restoreArchivedTab: (TabID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MobileArchiveList(
                space: space,
                restoreArchivedTab: restoreAndDismiss
            )
            .navigationTitle("\(space?.name ?? "Space") Archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func restoreAndDismiss(_ tabID: TabID) {
        restoreArchivedTab(tabID)
        dismiss()
    }
}
