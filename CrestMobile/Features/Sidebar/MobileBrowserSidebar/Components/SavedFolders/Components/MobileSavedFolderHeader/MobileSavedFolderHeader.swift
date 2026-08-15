import SwiftUI

struct MobileSavedFolderHeader: View {
    let folder: SavedFolder
    let depth: Int
    let isExpanded: Bool
    let isEditing: Bool
    @Binding var draftTitle: String
    let toggleExpansion: () -> Void
    let commitTitle: () -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 7) {
                    MobileSavedFolderIcon(
                        folder: folder,
                        isExpanded: isExpanded
                    )

                    TextField("Folder Name", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(commitTitle)

                    Spacer(minLength: 8)
                }
                .mobileFolderHeaderLayout(depth: depth)
            } else {
                Button(action: toggleExpansion) {
                    HStack(spacing: 7) {
                        MobileSavedFolderIcon(
                            folder: folder,
                            isExpanded: isExpanded
                        )

                        Text(folder.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .mobileFolderHeaderLayout(depth: depth)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear(perform: synchronizeEditing)
        .onChange(of: isEditing) { _, _ in
            synchronizeEditing()
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditing {
                commitTitle()
            }
        }
    }

    private func synchronizeEditing() {
        guard isEditing else {
            isTitleFocused = false
            return
        }
        draftTitle = folder.title
        Task { @MainActor in
            isTitleFocused = true
        }
    }
}

#Preview("Mobile Saved Folder Header", traits: .sizeThatFitsLayout) {
    @Previewable @State var draftTitle = "Reading"
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSavedFolderHeader(
        folder: fixture.folder,
        depth: 0,
        isExpanded: true,
        isEditing: false,
        draftTitle: $draftTitle,
        toggleExpansion: {},
        commitTitle: {}
    )
    .frame(width: 340)
    .padding()
}
