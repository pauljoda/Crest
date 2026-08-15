import SwiftUI

struct MobileHistoryContent: View {
    let space: BrowserSpace?
    let clearHistory: () -> Void
    let openURL: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var confirmsClear = false

    var body: some View {
        NavigationStack {
            MobileHistoryList(
                space: space,
                searchText: searchText,
                openHistoryEntry: openAndDismiss
            )
            .navigationTitle("\(space?.name ?? "Space") History")
            .searchable(text: $searchText, prompt: "Search this Space")
            .toolbar { historyToolbar }
            .confirmationDialog(
                "Clear history for \(space?.name ?? "this Space")?",
                isPresented: $confirmsClear,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive, action: clearHistory)
            } message: {
                Text("History in other Spaces is not affected.")
            }
        }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if !(space?.history ?? []).isEmpty {
                Button("Clear", role: .destructive) { confirmsClear = true }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: dismiss.callAsFunction)
        }
    }

    private func openAndDismiss(_ entry: BrowserHistoryEntry) {
        openURL(entry.url)
        dismiss()
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    MobileHistoryContent(
        space: fixture.space,
        clearHistory: {},
        openURL: { _ in }
    )
}
