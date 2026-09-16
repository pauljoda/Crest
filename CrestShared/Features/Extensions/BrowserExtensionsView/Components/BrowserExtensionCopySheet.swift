import SwiftUI

struct BrowserExtensionCopySheet: View {
    let summary: BrowserExtensionSummary
    let sourceSpace: BrowserSpace
    let pool: BrowserExtensionControllerPool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpaces: Set<SpaceID> = []
    @State private var isInstalling = false
    @State private var failure: String?

    var body: some View {
        let destinations = pool.copyDestinations(extensionID: summary.id, excluding: sourceSpace.id)
        let eligibleSelection = selectedSpaces.intersection(Set(destinations.map(\.id)))
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            Text("Install a Copy in Other Spaces")
                .font(.title2.bold())
            Text(summary.displayName)
                .font(.headline)
            Text(
                "Copies use the current permissions from \(sourceSpace.name). Each Space keeps its own extension data; existing data is not copied."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            BrowserExtensionSpaceSelectionList(
                spaces: destinations,
                selection: $selectedSpaces
            )
            .disabled(isInstalling)
            if let failure {
                Text(failure).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isInstalling)
                Spacer()
                if isInstalling { ProgressView().controlSize(.small) }
                Button("Install Copies") {
                    isInstalling = true
                    failure = nil
                    Task { @MainActor in
                        defer { isInstalling = false }
                        do {
                            try await pool.copyExtension(
                                extensionID: summary.id, from: sourceSpace.id, to: eligibleSelection)
                            dismiss()
                        } catch { failure = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling || eligibleSelection.isEmpty)
            }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(idealWidth: 480)
        .interactiveDismissDisabled(isInstalling)
    }
}
